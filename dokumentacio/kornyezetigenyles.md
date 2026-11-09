# Környezetigénylési folyamat – Project X miniplatform (Infrastructure as Code)

Ebben a dokumentumban leírom, hogyan működik nálam az új futtatókörnyezetek igénylése és kiszolgálása. Két nézőpontot rögzítek:

1. **A fejlesztői oldal:** mit kell tennie egy fejlesztőnek, ha új környezetet szeretne kapni (3. fejezet).
2. **Az üzemeltetői oldal:** mit csinálok én platform engineerként, amikor beérkezik egy igénylés (4. fejezet).

A folyamat alapja a `project-x` **sandbox** (`sbx`) és **dev** környezet. Ezeket először kézzel (ClickOps) építettem fel, majd a 3.0-s verzióban **teljes egészében Terraform-kódba ültettem át**. A leírás egyszerre szolgál dokumentációként és futtatókönyvként (runbookként): a 4. fejezet lépései sorban végrehajthatók, és a repóban lévő scriptek pontosan ezeket a lépéseket vezénylik le.

**Az alap DNS-zónám:** `vighsandor.az.cubix-pe.hu`. Minden környezet ez alá kap saját alzónát.

**A repó:** <https://github.com/vighsandor/cubixplatformeng>, `platformeng-w3` ág, `week3-iac` tag.

### Változásnapló

| Verzió | Tartalom |
|---|---|
| 1.0 | ClickOps-alapinfrastruktúra: AKS, Traefik, Azure DNS alzóna kézi A rekordokkal, cert-manager, Let's Encrypt |
| 2.0 | Entra ID-integráció és automatikus DNS: jogosultság csak Entra ID-csoportoknak; External DNS managed identityvel és workload identity federationnel, titok nélkül |
| **3.0** | **Infrastructure as Code.** Az Azure- és Entra ID-erőforrások (resource groupok, hálózat, AKS, identitások, federated credential, DNS-zóna és delegáció, csoportok, tagságok, szerepkörök) Terraformból jönnek létre, környezetenként külön kódkönyvtárban és külön state-tel (4.2–4.4). A Kubernetesen belüli komponensek ezen a szinten még szándékosan kézi, Helm-es lépések maradnak (4.6). A létrehozást és a lebontást scriptek vezénylik le (4.3, 4.10). A portálos ClickOps-lépések kikerültek a futtatókönyvből. |

**A dokumentumban használt változók:**

| Változó | Jelentés | Példa |
|---|---|---|
| `<projekt>` | A projekt rövid azonosítója | `project-x` |
| `<env>` | A környezet rövid jele: `sbx`, `dev`, `test` | `dev` |
| `<app>` | Az alkalmazás (hosztnév) rövid neve | `colors` |

---

## 1. Mit ad a platform? Képességek és megkötések

**Miért van szükség platformra?** Platform nélkül minden fejlesztőcsapat maga építené fel ugyanazokat az infrastrukturális alapokat. Ebből három probléma következik: ugyanazt a munkát többször végzik el, a csapatok eltérő, nem standardizált megoldásokra jutnak, és a fejlesztőkre olyan teher kerül, ami nem a fő feladatuk. A platform ezt úgy oldja meg, mint egy kollégium. Én adom az infrastruktúrát (a „szobát” és a közműveket), a projekt pedig csak beköltözik. Cserébe a platformnak a képességei mellett **szabályai is vannak**, és ezeket a platform be is tartatja.

### 1.1 Képességek

Minden igényelt környezet egy **önálló, minimális, de teljes értékű AKS-alapú futtatókörnyezet**:

| Képesség | Megvalósítás |
|---|---|
| Kubernetes cluster | Azure Kubernetes Service (AKS), egy `system` node pool |
| Hozzáférés | Microsoft Entra ID-alapú bejelentkezés; Azure RBAC jogosultságok Entra ID-csoportokon keresztül; helyi fiókok tiltva |
| HTTP(S) belépési pont | Traefik ingress controller Azure Load Balancerrel; minden HTTP kérést HTTPS-re irányít át |
| Névfeloldás | Saját Azure DNS alzóna: `<projekt>.<env>.vighsandor.az.cubix-pe.hu`. A rekordokat az External DNS automatikusan létrehozza az Ingress-erőforrások alapján. |
| TLS-tanúsítvány | cert-manager, Let's Encrypt `ClusterIssuer` (`letsencrypt`) |
| Gépi identitás | Workload identity federation: a clusterben futó platformkomponensek titkos kulcs nélkül, managed identityvel érik el az Azure-t |
| Reprodukálhatóság | Minden környezet ugyanabból a Terraform-kódból, verziókezelten jön létre; két környezet között csak a `terraform.tfvars` és a state helye különbözik |

Az eredmény: a fejlesztő egyetlen Ingress-erőforrással **névvel elérhető, TLS-sel védett** végpontot kap, emberi beavatkozás nélkül.

### 1.2 Megkötések és a mögöttük álló döntéseim

| Terület | Szabály | Indoklás |
|---|---|---|
| Régió | Sweden Central | Itt van biztosított kvótám, és minden környezet egy helyen fut. |
| Méret | 1 node, `Standard_D2as_v5` (2 vCPU, 8 GiB RAM) | A kvóta szűkös: a Standard DASv5 családra 4 vCPU, a régióra összesen 8 vCPU jut. Nagyobb gépet csak indoklással adok. |
| Frissítés | Az automatikus frissítés ki van kapcsolva | Rövid életű, eltakarítandó környezetekről van szó; a verziót én tartom kézben (Terraform-változó). |
| **Infrastruktúra-változtatás** | **Csak kódból, `terraform plan` + `apply` útján; a portálon kézzel nem módosítok** | A kód az egyetlen igazságforrás. Egy kézi módosítás eltérést (driftet) okoz, amelyet a következő `apply` visszaír, vagy ami rosszabb, összeakad vele. A `plan` minden változtatás előtt megmutatja, mi fog történni. |
| Jogosultság | Jogot csak Entra ID-csoport kap, személy soha | Csoportokkal a jogosultságkezelés skálázható és követhető. Ha valaki elhagyja a projektet, elég kivenni a csoportból. |
| Gépi hozzáférés | Titkos kulcsot nem használok; a gépi identitás managed identity, federated credentiallel | A lejáró, kézzel forgatandó titkok kezelése hibalehetőség és biztonsági kockázat. |
| Legkisebb jogosultság | Az External DNS identitása csak *DNS Zone Contributor* szerepkört kap, és csak a saját környezete alzónáján | Ha egy környezet komponense kompromittálódik, más környezet DNS-éhez akkor sem fér hozzá. |
| DNS | A hosztnevek automatikusan jönnek létre, de csak a környezet saját alzónáján belül | Az External DNS `domainFilters` beállítása a zónán kívüli hosztneveket figyelmen kívül hagyja. |
| TLS | Let's Encrypt **staging** végpont | Az éles Let's Encrypt ugyanarra a névre nagyjából heti 5 tanúsítványt ad ki; a stagingnél ez a korlát jóval magasabb, így szabadon lehet újraépíteni. Ára, hogy a böngésző „nem biztonságos” figyelmeztetést ad. |
| Élettartam | A lejárati dátum után megszüntetem a környezetet, ha nem kérik a meghosszabbítását | A nem használt infrastruktúra pénzbe kerül és foglalja a kvótát. Terraformmal a teljes lebontás és az újraépítés is egyetlen parancs. |

---

## 2. Elnevezési konvenció

Minden erőforrás nevébe beleteszem a **projekt** és a **környezet** jelét, a komponensek nevében pedig a **komponens** nevét is. A Terraform-kódban ezt egyetlen származtatott érték biztosítja: `local.resource_basename = "${var.project_name}-${var.env_name}"`. A nevek így nem gépelhetők el, és két környezet nem ütközhet.

### 2.1 Azure-erőforrások

| Erőforrás | Minta | `sbx` | `dev` | Terraform-erőforrás |
|---|---|---|---|---|
| Resource group (AKS) | `<projekt>-<env>-aks` | `project-x-sbx-aks` | `project-x-dev-aks` | `azurerm_resource_group.aks` |
| AKS cluster | `<projekt>-<env>` | `project-x-sbx` | `project-x-dev` | `azurerm_kubernetes_cluster.aks` |
| Infrastruktúra (node) resource group | `<projekt>-<env>-aks-nodes` | `project-x-sbx-aks-nodes` | `project-x-dev-aks-nodes` | (az AKS hozza létre) |
| Virtuális hálózat | `<projekt>-<env>-network` | `10.224.0.0/12` | `10.224.0.0/12` | `azurerm_virtual_network.aks` |
| Alhálózat (node-ok) | `<projekt>-<env>-aks-nodes` | `10.224.0.0/24` | `10.224.0.0/24` | `azurerm_subnet.aks_nodes` |
| Managed identity (AKS) | `<projekt>-<env>-aks` | `project-x-sbx-aks` | `project-x-dev-aks` | `azurerm_user_assigned_identity.aks` |
| Managed identity (External DNS) | `<projekt>-<env>-externaldns` | `project-x-sbx-externaldns` | `project-x-dev-externaldns` | `azurerm_user_assigned_identity.external_dns` |
| Federated credential (External DNS) | `external-dns` | `external-dns` | `external-dns` | `azurerm_federated_identity_credential.external_dns` |
| AKS DNS name prefix | `<projekt>-<env>-dns` | `project-x-sbx-dns` | `project-x-dev-dns` | (az AKS argumentuma) |
| Resource group (DNS) | `<projekt>-<env>-dns` | `project-x-sbx-dns` | `project-x-dev-dns` | `azurerm_resource_group.dns` |
| DNS alzóna | `<projekt>.<env>.vighsandor.az.cubix-pe.hu` | `project-x.sbx.…` | `project-x.dev.…` | `azurerm_dns_zone.env` |
| NS-delegáció a szülőzónában | `<projekt>.<env>` | `project-x.sbx` | `project-x.dev` | `azurerm_dns_ns_record.delegation` |
| Terraform state (blob) | `<projekt>-<env>.tfstate` | `project-x-sbx.tfstate` | `project-x-dev.tfstate` | (backend) |

### 2.2 Entra ID-csoportok

| Csoport | Minta | Tagok | Szerepkörök a clusteren |
|---|---|---|---|
| Platformadminok | `<projekt>-<env>-platform-admins` | a Terraformot futtató identitás (én) + `additional_platform_admin_object_ids` | Azure Kubernetes Service **RBAC Cluster Admin**, **Cluster User Role** |
| Fejlesztők (írás) | `<projekt>-<env>-developers` | `developer_object_ids` (igénylőlap 5. pont) | Azure Kubernetes Service **RBAC Writer**, **Cluster User Role** |
| Olvasók | `<projekt>-<env>-readers` (csak ha van tagja) | `reader_object_ids` (igénylőlap 5. pont) | Azure Kubernetes Service **RBAC Reader**, **Cluster User Role** |

A csoportok **Security** típusúak; a tagságot a Terraform kezeli (`azuread_group_member`).

### 2.3 Kubernetes-objektumok

| Objektum | Név |
|---|---|
| Namespace-ek (platform) | `ingress-controller`, `cert-manager`, `external-dns` |
| Namespace (alkalmazás) | `<app>` |
| External DNS service account | `external-dns` (az `external-dns` namespace-ben) |
| External DNS TXT owner ID | az alzóna neve, a pontok kötőjelre cserélve (Terraform-kimenet: `external_dns_txt_owner_id`) |

**Hálózati tervezés:** minden környezet saját, át nem fedő `/12` VNet-tartományt kap, hogy egy későbbi peering ne igényeljen újraépítést. A Kubernetes service-tartomány (`10.0.0.0/16`, DNS IP: `10.0.0.10`) clusteren belüli, ezért minden környezetben ugyanaz.

---

## 3. Fejlesztői folyamat: hogyan igényelj környezetet?

Ez a fejezet a fejlesztőknek szól. Leírom, mit kérek tőled, és mit kapsz tőlem cserébe. A 3.0-s verzióban a te oldaladon **nem változott semmi**: az, hogy a környezetet kódból építem fel, számodra annyit jelent, hogy gyorsabban és mindig ugyanúgy kapod meg.

### 3.1 A folyamat áttekintése

```
Fejlesztő (te)                          Platform engineer (én)
──────────────                          ──────────────────────
1. Kitöltöd az igénylőlapot      ──►    2. Befogadom és ellenőrzöm az igénylést
                                        3. Felveszem a környezetet a kódba,
                                           és Terraformmal felépítem
                                        4. Ellenőrzöm, majd átadom
5. Megkapod az átadó üzenetet    ◄──
6. Csatlakozol, telepíted az alkalmazásod
   (a DNS-név és a TLS-tanúsítvány automatikusan elkészül)
7. Lejárat előtt jelzel: meghosszabbítás vagy megszüntetés
```

### 3.2 1. lépés: készülj fel

1. Ellenőrizd, hogy van **Entra ID-fiókod** a céges tenantban. A clusterbe ezzel fogsz belépni, és ezzel veszlek fel a projekt csoportjába.
2. Telepítsd a szükséges eszközöket: `az` (Azure CLI), `kubectl`, `kubelogin` (Azure kubelogin plugin), `helm`. A `k9s` nem kötelező, de kényelmes.
3. Döntsd el előre:
   - a **projekt azonosítóját**: rövid, kisbetűs, kötőjeles, például `project-x`;
   - a **környezet típusát**: `sbx` kísérletezésre, `dev` közös fejlesztésre;
   - **kiknek** kell hozzáférés, és milyen szinten (írás vagy olvasás);
   - **meddig** lesz szükséged a környezetre.

### 3.3 2. lépés: küldd be az igénylést

Az igényléshez egy Markdown-formátumú igénylőlapot használok. Így az igénylés verziókezelhető, géppel is jól feldolgozható, és nem kell hozzá külső eszköz.

1. Másold le az **igénylőlap sablonját** az [A. függelékből](#a-függelék--környezetigénylő-lap-markdown-sablon) egy új fájlba, ezen a néven: `igenyles-<projekt>-<env>.md`.
2. Töltsd ki a mezőket: a `<…>` helyekre írd be az értéket, a választós kérdéseknél pedig jelöld be a megfelelő négyzetet (`- [x]`).
3. Küldd el nekem a kitöltött fájlt e-mailben vagy a csapat csatornáján.

> **Hosztnevet nem kell előre igényelned.** A DNS-rekordok automatikusan jönnek létre abból a hosztnévből, amelyet az Ingress-erőforrásodban megadsz (lásd 3.6).

### 3.4 3. lépés: várd meg a visszajelzésemet

1. **2 munkanapon belül** visszajelzek: vagy jóváhagyom az igénylést, vagy kérdezek.
2. A jóváhagyás után felépítem a környezetet, felveszlek a megfelelő Entra ID-csoportba, és **átadó üzenetet** küldök a cluster adataival, a DNS-zónával, a csoport nevével, a csatlakozás parancsaival és egy működő demóalkalmazás URL-jével.

### 3.5 4. lépés: csatlakozz a clusterhez

```bash
az login
az account set --subscription <ELŐFIZETÉS-AZONOSÍTÓ>
az aks get-credentials --resource-group <projekt>-<env>-aks --name <projekt>-<env> --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

**Sikeres, ha** a `kubectl get nodes` kiír egy node-ot `Ready` állapotban.

> Ha 403 / Forbidden hibát kapsz, pedig az átadó üzenet szerint már tagja vagy a csoportnak, jelentkezz ki és be újra (`az logout`, majd `az login`). A csoporttagság átvezetése néhány percig is tarthat.

### 3.6 5. lépés: telepítsd az alkalmazásod

Az alkalmazás Ingress-erőforrásán két dolgot kell beállítanod:

1. A **host** a környezeted alzónáján belül legyen: `<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu`. Az `<app>` előtagot te választod.
2. Az Ingress kapja meg a **`cert-manager.io/cluster-issuer: letsencrypt`** annotációt.

```bash
helm upgrade --install \
    --namespace=<app> --create-namespace \
    <app> \
    <chart-referencia> \
    --set ingress.host=<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu \
    --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt
```

Ezután automatikusan: az **External DNS** 1–2 percen belül létrehozza az A rekordot (és a hozzá tartozó TXT rekordot), a **cert-manager** tanúsítványt kér, és néhány perc múlva az alkalmazás elérhető a `https://<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu` címen.

> - **Zónán kívüli hosztnév nem működik:** az External DNS figyelmen kívül hagyja.
> - **Az Ingress törlésekor a DNS-rekord is törlődik**, így nem maradnak árva rekordok.
> - Az `ingress-controller`, a `cert-manager` és az `external-dns` namespace a platform része; kérlek, **ne módosítsd őket**.

### 3.7 Módosítás, meghosszabbítás, megszüntetés

- **Új hosztnév kell?** Nem kell igényelned, csak hozz létre hozzá Ingresst.
- **Új csapattag, kilépő tag, más méret?** Küldj igénylést „Módosítás” típussal. A változást a kódban vezetem át (4.9), így az is nyomon követhető, ki és mikor kapott jogot.
- **Meghosszabbítás:** a lejárat előtt legalább 3 munkanappal jelezd.
- **Már nincs rá szükség?** Szólj, és előbb lebontom.

---

## 4. Üzemeltetői folyamat: így építem fel a környezetet (Terraform)

Ez a fejezet az én futtatókönyvem. Minden lépésnél leírom, mit csinálok, milyen eredményt várok, és miért így döntöttem.

### 4.0 Miért Terraform, és mit tanultam az átültetésből?

**Deklaratív vs. imperatív.** A ClickOps és a parancssoros scriptek (`az ... create`) imperatívak: lépéseket írnak le, és a végeredmény attól függ, honnan indultunk. A Terraform deklaratív: a kód a **kívánt állapotot** írja le. A Terraform ezt összeveti a saját nyilvántartásával (**state**), és a `plan` megmutatja, mit kell létrehozni, módosítani vagy törölni, hogy a valóság a kódnak megfeleljen. Az `apply` ezt hajtja végre. Ugyanaz a kód többször lefuttatva sem csinál semmit, ha nincs eltérés.

**Mit nyerek vele a ClickOps-hoz és a scriptekhez képest?**

- **Az állapotok összehasonlíthatók és verziózhatók.** Az imperatív scriptnél csak a lépéseket tudom verziózni. Itt magát az infrastruktúrát: a gitben egy diff azt mutatja, hogy januárban még `Standard_D2as_v5` volt a node-méret, februárban már más.
- **A konfigurációs drift felderíthető.** Drift az, amikor a valós állapot egy ponton még megegyezett a kívánttal, de utána eltért tőle, mert valaki kézzel módosított, vagy a platform maga változott. Mivel a kívánt állapot le van írva, a `plan` megmutatja az eltérést. Imperatív eszközökkel ez nem, vagy csak nagy nehezen oldható meg.
- **A változtatás a kívánt állapot átírása.** Az Azure CLI-vel egy átnevezéshez nekem kellene kiadnom a törlést és az új létrehozását; ha csak az újat hozom létre, a régi szemétként ott marad. Terraformban csak a nevet írom át, a `plan` pedig jelzi, hogy az erőforrás cserére kerül (*must be replaced*). Ezt a jelzést mindig komolyan veszem: az AKS sok argumentuma (pl. a `network_profile` vagy a `node_resource_group`) csak újraépítéssel módosítható.

**Ahol az imperatív eszköz a jobb választás.** A hibakeresés (naplók, események: `kubectl logs`, `az ... show`) és az egyszeri migrációs lépések, ahol a deklaratív eszköz a régi erőforrást az adataival együtt törölné. Ezeket továbbra is kézzel, imperatívan végzem. A Kubernetesen belüli rész ezen a szinten Helmmel megy, amely legalább a release-ek szintjén összehasonlítja a kívánt és a meglévő állapotot. Ezt később egy Kubernetes-natív deklaratív eszköz (Argo CD) veszi át.

**A portál sokat elrejt.** Az átültetés legfontosabb tanulsága: a portál menet közben, a háttérben számos erőforrást létrehozott helyettem, amit Terraformban nekem kell kifejezetten leírnom:

| Amit a portál „magától” csinált | Terraformban |
|---|---|
| *Create new* resource group, VNet, subnet, managed identity | külön `azurerm_resource_group`, `azurerm_virtual_network`, `azurerm_subnet`, `azurerm_user_assigned_identity` |
| *Network Contributor* jog a cluster identitásának az alhálózaton | `azurerm_role_assignment` (a clusternek **függenie kell** tőle: `depends_on`) |
| *„Child of an existing zone”* → NS-delegáció a szülőzónában | `azurerm_dns_ns_record` a szülőzónában, az alzóna névszervereivel |
| Csoport létrehozása tagokkal | `azuread_group` + `azuread_group_member` |

**A sorrendet a Terraform számolja ki.** A portálon lineárisan, lépésről lépésre haladtam. Terraformban az erőforrások közötti hivatkozásokból (pl. a federated credential az AKS `oidc_issuer_url`-jére hivatkozik) a Terraform maga építi fel a függőségi gráfot, és párhuzamosít, ahol lehet.

**A kód szervezése.** A fájlokat a **funkció** szerint bontom, nem típus szerint: ami a DNS-hez kell (a zóna, a delegáció, az External DNS identitása és szerepköre), az a `dns.tf`-ben van. Így egy funkció változtatásakor egy helyen kell dolgoznom. A Terraformnak mindegy, a fájlhatár az embernek szól.

### 4.1 Előfeltételek

1. Telepített eszközök: `az`, `terraform` (≥ 1.4), `kubectl`, `kubelogin`, `helm`, `curl`.
2. Bejelentkezés: `az login`. A Terraform providerek az Azure CLI bejelentkezését használják, és a `provider.tf`-ben rögzített előfizetésben és tenantban dolgoznak, függetlenül attól, hogy az `az` éppen melyik előfizetésre mutat.
3. **Terraform state backend.** A state nem a gépemen, hanem Azure Storage-ban él, hogy perzisztens legyen, és később egy pipeline is ugyanazt használhassa:

   | Elem | Érték |
   |---|---|
   | Resource group | `course-baseline` (a kurzus elején, kézzel; ezt a kód nem kezeli) |
   | Storage account | `platencbvighsandor` (swedencentral, Standard_LRS; a név globálisan egyedi). Az oktató a westeuropet használta, de az az előfizetésemben új ügyfelet nem fogad (*RequestDisallowedByAzure*), ezért a többi erőforrással azonos régiót választottam. |
   | Container | `tfstate` |
   | Blob (kulcs) | `<projekt>-<env>.tfstate` (környezetenként külön) |
   | Jogosultság | **Storage Blob Data Contributor** a storage accounton (a saját felhasználómnak) |

   > Az *Owner* szerepkör nem elég: az Azure-ban az adat-jogosultságok (data actions) elválnak az adminisztratív jogoktól, ezért a blobok olvasásához-írásához külön *Storage Blob Data Contributor* kell. A létrehozó script ellenőrzi, és ha hiányzik, pótolja a storage accountot, a containert és a szerepkört.

4. A `vighsandor.az.cubix-pe.hu` szülőzóna megvan a `course-baseline` resource groupban. A kód ezt csak olvassa (`data "azurerm_dns_zone"`), soha nem módosítja, kivéve a saját NS-delegációs rekordját.
5. **Nincs ütköző, kézzel létrehozott erőforrás.** Ha egy erőforrás már létezik (pl. egy korábbi ClickOps-csoport az Entra ID-ban), a Terraform nem veszi át, hanem hibát ad. Az Entra ID-objektumok nem a resource groupokban élnek, ezért a portálos takarításnál ezekre külön figyelni kell.

### 4.2 A kód felépítése

```
.
├── terraform/
│   ├── sbx/                     # a sandbox kódja és state-pillanatképe
│   │   ├── provider.tf          # Terraform, backend (state helye), providerek
│   │   ├── common.tf            # közös változók, locals (nevek, tagek), client config
│   │   ├── network.tf           # VNet, alhálózat, Network Contributor a clusternek
│   │   ├── aks.tf               # RG, cluster-identitás, AKS, Entra ID-csoportok, tagságok, RBAC
│   │   ├── dns.tf               # alzóna, NS-delegáció, External DNS identitás + federáció + jog
│   │   ├── outputs.tf           # a K8s-lépésekhez és az átadáshoz szükséges értékek
│   │   ├── terraform.tfvars     # a környezet egyedi értékei
│   │   ├── .terraform.lock.hcl  # rögzített providerverziók
│   │   └── state/               # state-pillanatkép a beadandóhoz
│   └── dev/                     # ugyanez a dev környezetre
├── k8s/                         # ClusterIssuer, External DNS values-sablon
├── scripts/                     # létrehozó, lebontó és segédscriptek
├── segedscript/                 # az oktatói segédscript (változatlanul)
├── kimenetek/                   # a segédscript- és curl-kimenetek
└── dokumentacio/                # ez a dokumentum és az igénylőlap
```

**Rögzített verziók:** Terraform ≥ 1.4, `hashicorp/azurerm` **5.3.0**, `hashicorp/azuread` **3.9.0**. A pontos verzió és a lock fájl biztosítja, hogy a kód ma és fél év múlva is ugyanúgy viselkedjen.

**Két környezet, két könyvtár.** A `sbx` és a `dev` könyvtár kódja **szándékosan azonos**, csak két helyen tér el:

| Fájl | Mi különbözik | `sbx` | `dev` |
|---|---|---|---|
| `provider.tf` | a backend `key`-e (a state blobja) | `project-x-sbx.tfstate` | `project-x-dev.tfstate` |
| `terraform.tfvars` | `env_name`, VNet-tartomány, lejárat, tagok | `sbx`, `10.224.0.0/12` | `dev`, `10.224.0.0/12` |

> Ez a kódduplikáció tudatos, átmeneti kompromisszum: így a két környezet state-je és életciklusa teljesen független, és a kód egyszerűen olvasható. A következő lépésben a közös részt modulba emelem, és a könyvtárak csak a modul paraméterezését tartalmazzák.

**A Terraform által kezelt erőforrások környezetenként:**

| Fájl | Erőforrások |
|---|---|
| `common.tf` | `data.azurerm_client_config.current` |
| `network.tf` | `azurerm_virtual_network.aks`, `azurerm_subnet.aks_nodes`, `azurerm_role_assignment.aks_subnet_network_contributor` |
| `aks.tf` | `azurerm_resource_group.aks`, `azurerm_user_assigned_identity.aks`, `azurerm_kubernetes_cluster.aks`, `azuread_group.platform_admins`, `azuread_group.developers`, `azuread_group.readers` (ha van olvasó), `azuread_group_member.*`, `azurerm_role_assignment.aks[*]` |
| `dns.tf` | `data.azurerm_dns_zone.parent`, `azurerm_resource_group.dns`, `azurerm_dns_zone.env`, `azurerm_dns_ns_record.delegation`, `azurerm_user_assigned_identity.external_dns`, `azurerm_federated_identity_credential.external_dns`, `azurerm_role_assignment.external_dns_zone_contributor` |

**A fontosabb AKS-beállítások a kódban** (a ClickOps-os portálbeállítások megfelelői):

| ClickOps (portál) | Terraform (`azurerm_kubernetes_cluster`) |
|---|---|
| Pricing tier: Free | `sku_tier = "Free"` |
| Automatic upgrade: Disabled | `automatic_upgrade_channel` nincs megadva (= none) |
| Node security channel: None | `node_os_upgrade_channel = "None"` |
| Node pool `system`, `Standard_D2as_v5`, Manual, 1 node | `node_provisioning_profile { mode = "Manual" }`, `default_node_pool { name = "system", node_count = 1, vm_size = var.node_vm_size, vnet_subnet_id = … }` |
| Azure CNI Overlay, saját VNet | `network_profile { network_plugin = "azure", network_plugin_mode = "overlay", service_cidr, dns_service_ip }` |
| User assigned managed identity | `identity { type = "UserAssigned", identity_ids = [...] }` |
| Entra ID authentication with Azure RBAC | `azure_active_directory_role_based_access_control { azure_rbac_enabled = true }` |
| Local accounts: Disabled | `local_account_disabled = true` |
| OIDC + Workload Identity | `oidc_issuer_enabled = true`, `workload_identity_enabled = true` |
| Infrastructure RG neve | `node_resource_group = "<projekt>-<env>-aks-nodes"` |

### 4.3 Új környezet felvétele a kódba

Ha az igénylés **új környezetet** kér (a meglévő `sbx` és `dev` már a repóban van):

1. Átmásolom egy meglévő környezet könyvtárát (a `state/` mappa nélkül):

   ```bash
   cp -r terraform/dev terraform/<env> && rm -rf terraform/<env>/state terraform/<env>/.terraform
   ```

2. A `terraform/<env>/provider.tf`-ben átírom a backend kulcsát: `key = "<projekt>-<env>.tfstate"`.
3. A `terraform/<env>/terraform.tfvars`-ban kitöltöm az igénylőlap alapján:

   ```hcl
   project_name = "<projekt>"
   env_name     = "<env>"
   expires      = "<lejárat, ÉÉÉÉ-HH-NN>"

   vnet_address_space = "<a következő szabad /12>"
   node_subnet_prefix = "<annak első /24-e>"

   developer_object_ids = ["<object ID>", ...]   # igénylőlap 5. pont, Írás
   reader_object_ids    = []                     # igénylőlap 5. pont, Olvasás
   ```

   Az e-mail-címekhez tartozó object ID-t így kérdezem le: `az ad user show --id <e-mail> --query id -o tsv`.

4. A változtatást commitolom; a környezet ettől kezdve a kódban él.

### 4.4 1. lépés – Az infrastruktúra létrehozása (Terraform)

A teljes folyamatot (4.4–4.7) a létrehozó script vezényli le:

```bash
./scripts/sbx-letrehozas.sh        # vagy: ./scripts/dev-letrehozas.sh
                                   # általánosan: ./scripts/kornyezet-letrehozas.sh <env>
```

A script először a Terraform-részt futtatja. Kézzel ugyanez:

```bash
cd terraform/<env>
terraform init                 # providerek letöltése, backend (state) bekötése
terraform plan -out=tfplan     # mit fog csinálni? – ezt mindig elolvasom
terraform apply tfplan         # pontosan a jóváhagyott tervet hajtja végre
```

> **Miért `plan -out` + `apply tfplan`?** Így az `apply` nem számol új tervet, hanem pontosan azt hajtja végre, amit átnéztem és jóváhagytam. A script a `plan` után megerősítést kér (`igen`), és csak utána alkalmazza. Pipeline-ban ugyanez a minta: egy lépés tervez, jóváhagyás után egy másik végrehajt.

**Elvárt eredmény:** a `plan` 20–25 létrehozandó erőforrást mutat, módosítást és törlést nem. Az `apply` 5–10 perc (ennek nagy része az AKS), a végén `Apply complete!` és a kimenetek (`outputs`).

**A Terraform-kimenetek**, amelyekre a következő lépéseknek szükségük van:

```bash
terraform output
# aks_name, aks_resource_group, aks_oidc_issuer_url, dns_zone_name,
# dns_resource_group, external_dns_client_id, external_dns_txt_owner_id, ...
```

### 4.5 2. lépés – Csatlakozás a clusterhez

```bash
az aks get-credentials -g "$(terraform output -raw aks_resource_group)" -n "$(terraform output -raw aks_name)" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

**Elvárt eredmény:** egy `aks-system-…` node `Ready` állapotban. Ezzel azt is igazoltam, hogy a Terraformmal létrehozott csoporttagság és szerepkör működik. A szerepkör életbe lépése néhány percig tarthat; a script ezért legfeljebb 10 percig újrapróbálkozik.

### 4.6 3. lépés – Kubernetesen belüli komponensek (kézi, Helm)

A Kubernetesen belüli komponenseket ezen a szinten még **szándékosan nem Terraformmal** telepítem, hanem a megszokott Helm-parancsokkal. A paramétereiket viszont már nem kézzel másolom a portálról, hanem a **Terraform-kimenetekből** veszem. A sorrend számít: a demóalkalmazás telepítésekor már futnia kell az External DNS-nek és a cert-managernek.

1. **Traefik:**

   ```bash
   helm upgrade --install traefik traefik \
     --repo https://traefik.github.io/charts --version 41.2.0 \
     --namespace ingress-controller --create-namespace \
     --set service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
     --set ports.web.http.redirections.entryPoint.to=websecure \
     --set ports.web.http.redirections.entryPoint.scheme=https \
     --set ports.web.http.redirections.entryPoint.permanent=true
   ```

2. **External DNS:** a values fájlt a `k8s/external-dns.values.tmpl.yaml` sablonból töltöm ki:

   | Sablonhely | Terraform-kimenet |
   |---|---|
   | `__TXT_OWNER_ID__` | `external_dns_txt_owner_id` |
   | `__DNS_ZONE__` | `dns_zone_name` |
   | `__CLIENT_ID__` | `external_dns_client_id` |
   | `__SUBSCRIPTION_ID__` | `subscription_id` |
   | `__IDENTITY_RG__` | `aks_resource_group` (a managed identity resource groupja) |
   | `__DNS_RG__` | `dns_resource_group` (a DNS-zóna resource groupja) |

   ```bash
   helm upgrade --install external-dns external-dns \
     --repo=https://kubernetes-sigs.github.io/external-dns/ --version=1.20.0 \
     --namespace=external-dns --create-namespace \
     --values=k8s/external-dns.<env>.values.yaml
   ```

   > A Client ID-t korábban a portálról másoltam ki, és egyszer egy törölt, azonos nevű identitás régi azonosítója került a fájlba. A Terraform-kimenetből ez a hiba nem fordulhat elő.

3. **cert-manager és ClusterIssuer:**

   ```bash
   helm upgrade --install cert-manager cert-manager \
     --version=v1.19.4 --repo=https://charts.jetstack.io \
     --namespace=cert-manager --create-namespace \
     --set crds.enabled=true --set prometheus.enabled=false
   kubectl apply -f k8s/cluster-issuer.yaml    # letsencrypt (staging), platformengineer@vighsandor.hu
   ```

4. **Demóalkalmazás (smoketest):**

   ```bash
   helm upgrade --install --namespace=colors --create-namespace colors \
     oci://docker.io/ecklm/colors-demo-app \
     --set ingress.host=colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu \
     --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt
   ```

**Elvárt eredmény:** 1–2 percen belül megjelenik a `colors` A és TXT rekord az alzónában; néhány perc múlva a tanúsítvány `READY=True`.

### 4.7 4. lépés – Ellenőrzés és dokumentálás

A létrehozó script a végén elvégzi, és a repóba menti:

1. **State-pillanatkép:** `terraform state pull` → `terraform/<env>/state/<projekt>-<env>.tfstate`, valamint a `terraform state list` → `terraform/<env>/state/<projekt>-<env>.state-list.txt`.

   > A state élő példánya a backendben (Azure Storage) van; a repóba csak a létrehozás utáni pillanatképet teszem a beadáshoz és az átláthatósághoz. A state-ben nincs titkos kulcs (helyi fiókok tiltva, a gépi identitások federáltak), de érzékeny adat (azonosítók, belső címek) igen, ezért éles környezetben a state **nem kerülne publikus repóba**.

2. **Segédscript:** az oktatói segédscriptet (B. függelék) a környezet Terraform-könyvtárában futtatom (a végén lévő `terraform state list` miatt), kimenet: `kimenetek/segedscript-kimenet-<env>.txt`. A scriptet nem módosítom; a futtatás előtt csak a kitöltendő helyeit töltöm ki az adott környezet neveivel (`<domain>` → az alzóna neve, az External DNS identitás neve, illetve `dev` esetén a `project-x-sbx` nevek → `project-x-dev`).
3. **Végpont:** `curl -sk https://colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu`, kimenet: `kimenetek/curl-<env>.txt`. Elvárt: HTML-válasz `<title>Rollouts Demo</title>`-lel.
4. **Beillesztés a dokumentációba:** `./scripts/kimenetek-beillesztese.sh` – a kimeneteket változtatás nélkül, code blockban beilleszti a C. függelékbe.

### 4.8 5. lépés – Átadás a fejlesztőnek

```text
Szia <név>!

Elkészült a(z) <projekt> projekt <env> környezete.

- Előfizetés: <ELŐFIZETÉS-AZONOSÍTÓ>
- Resource group: <projekt>-<env>-aks
- AKS cluster: <projekt>-<env>
- DNS-zóna: <projekt>.<env>.vighsandor.az.cubix-pe.hu
  (ezen belül bármilyen hosztnevet használhatsz, a DNS-rekord automatikusan létrejön)
- Ingress class: traefik, ClusterIssuer: letsencrypt (staging)
- Csoport, amelynek tagja lettél: <projekt>-<env>-developers (RBAC Writer)
- Demó: https://colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu

Csatlakozás:
  az login
  az aks get-credentials -g <projekt>-<env>-aks -n <projekt>-<env> --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli

A környezet lejárata: <dátum>. Hosszabbítási igényt kérlek 3 munkanappal előtte jelezz.
```

### 4.9 Módosítás (módosító igénylés)

Minden változtatás ugyanazon az úton megy: **kód → `plan` → átnézés → `apply` → commit**.

| Igény | Hol módosítok |
|---|---|
| Új fejlesztő / kilépő fejlesztő | `terraform.tfvars`: `developer_object_ids` / `reader_object_ids` |
| Meghosszabbítás | `terraform.tfvars`: `expires` |
| Más node-méret | `terraform.tfvars`: `node_vm_size = "..."` (a kvótát előtte ellenőrzöm) |
| Kubernetes-frissítés | `terraform.tfvars`: `kubernetes_version = "..."` |

```bash
cd terraform/<env>
terraform plan -out=tfplan    # pontosan a kért változást mutatja-e? semmi mást?
terraform apply tfplan
```

> Ha a `plan` olyan változást is mutat, amit nem kértem, az **drift**: valaki a portálon módosított valamit. Ilyenkor nem alkalmazom vakon, hanem kiderítem az okát, és vagy a kódot igazítom, vagy az `apply`-jal visszaállítom a kódban leírt állapotot.

### 4.10 Megszüntetés (lebontás)

```bash
./scripts/sbx-lebontas.sh        # vagy: ./scripts/dev-lebontas.sh
                                 # általánosan: ./scripts/kornyezet-lebontas.sh <env>
```

A script:

1. megerősítésként bekéri a környezet nevét;
2. eltávolítja a Kubernetesen belüli komponenseket: előbb az alkalmazást, hogy az External DNS még törölhesse a saját rekordjait, majd az External DNS-t, a cert-managert és a Traefiket (ez felszabadítja a load balancer publikus IP-jét);
3. lefuttatja a `terraform destroy`-t: ez törli **mindazt, amit a Terraform létrehozott**, az Entra ID-csoportokat, a tagságokat és az NS-delegációt is. ClickOps-szal ezekre külön kellett figyelnem, mert nem a resource groupokban élnek; a Terraform a state alapján ezeket is tudja;
4. törli a helyi kubeconfig-bejegyzést.

> A repóban lévő state-pillanatképhez a lebontás nem nyúl, az a létrehozás utáni állapotot dokumentálja. A `course-baseline` resource group (szülőzóna, state storage account) megmarad, mert minden környezet erre épül.

---

## 5. Hibaelhárítás

| Tünet | Ok | Teendő |
|---|---|---|
| `terraform init`: *403 … AuthorizationPermissionMismatch* | Hiányzik a *Storage Blob Data Contributor* a state storage accountján (az *Owner* nem elég) | Szerepkör kiosztása (a script megteszi), néhány perc várakozás |
| `terraform apply`: *… already exists – to be managed via Terraform this resource needs to be imported* | Az erőforrás kézzel (ClickOps) már létrejött | A régi erőforrás törlése (az Entra ID-csoportokat is!), vagy `terraform import` |
| `terraform apply`: kvótahiba | Elfogyott a DASv5- vagy a régiós vCPU-kvóta | Usage + quotas; kvótaemelés, `node_vm_size` másik családra (arra is kell kvóta), vagy egy nem használt környezet lebontása |
| `terraform apply`: *The size … is currently unavailable* | A VM-méret nem elérhető | `node_vm_size` módosítása |
| `Error acquiring the state lock` | Egy másik (vagy megszakadt) futás tartja a state zárolását | Ellenőrzöm, hogy tényleg nem fut-e más; ha nem, `terraform force-unlock <ID>` |
| A `plan` olyan változást mutat, amit nem kértem | Drift: kézi módosítás a portálon | Kiderítem az okát (4.9) |
| A `kubectl` 403 / Forbidden hibát ad | A szerepkör vagy a csoporttagság még nem lépett életbe | Néhány perc várakozás; `az logout`, `az login` |
| Az `external-dns` pod `CrashLoopBackOff`, vagy *AADSTS* hiba a naplóban | Hibás values (Client ID, resource group), vagy a federated credential nem egyezik | A values újragenerálása a Terraform-kimenetekből (4.6); a Workload Identity be van-e kapcsolva |
| Nem jön létre DNS-rekord | A host nincs a környezet alzónáján belül, vagy hibás a DNS resource group | Az Ingress hostjának és a values fájlnak az ellenőrzése |
| A tanúsítvány `pending`, nem lesz `READY` | A DNS-név még nem az ingress IP-jére mutat | `nslookup`, az External DNS naplója, várakozás |
| A böngésző „nem biztonságos” kapcsolatot jelez | Let's Encrypt staging tanúsítvány | Várt viselkedés; `curl -k` |
| A segédscriptben üres a VNet-lista | A segédscript a VNetet a `…-aks-nodes` resource groupban keresi, de a saját VNet a `…-aks` resource groupban van | Várt viselkedés, a segédscriptet nem módosítom; a VNet a `terraform state list`-ben és az `az group list` / `az resource list -g <projekt>-<env>-aks` kimenetben látszik |

---

## A. függelék – Környezetigénylő lap (Markdown-sablon)

Ezt a sablont másolja le és tölti ki a fejlesztő (lásd 3.3). Külön fájlként is elérhető: `dokumentacio/igenyleslap-sablon.md`. A sablon alján lévő részt én töltöm ki az igénylés kiszolgálása közben.

```markdown
# Környezetigénylés – Project platform

> **Kitöltési útmutató:** mentsd el ezt a fájlt `igenyles-<projekt>-<env>.md` néven. A `<…>` helyekre írd be az értéket, a választós kérdéseknél pedig a megfelelő sorban cseréld a `[ ]` jelet `[x]`-re. A `*` kötelező mezőt jelöl. A kitöltött fájlt küldd el a platform engineernek.

## 1. Az igénylés típusa *

- [ ] Új környezet
- [ ] Módosítás (tagok felvétele vagy eltávolítása, más méret)
- [ ] Meghosszabbítás
- [ ] Megszüntetés

## 2. Igénylő

| Mező | Érték |
|---|---|
| Név * | `<név>` |
| Entra ID e-mail-cím * | `<név@ceg.hu>` |
| Csapat * | `<csapat neve>` |
| Költséghely / jóváhagyó vezető * | `<költséghely, vezető neve>` |

## 3. Környezet

| Mező | Érték |
|---|---|
| Projekt azonosítója * (kisbetű, szám, kötőjel; legfeljebb 15 karakter, betűvel kezdődik) | `<projekt>` |
| Mire használjátok a környezetet? * | `<rövid leírás>` |

**Környezet típusa \***

- [ ] `sbx` – kísérletezés, egyéni sandbox
- [ ] `dev` – közös fejlesztési környezet
- [ ] `test` – tesztelés

## 4. Tervezett alkalmazások és hosztnevek (tájékoztató)

A DNS-rekordokat a platform automatikusan létrehozza az Ingress-erőforrásokból, ezért a hosztneveket **nem kell előre igényelni**. A tervezett neveket csak a kapacitástervezéshez kérem. A hosztnevek formája: `<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu`.

| # | Alkalmazás (hosztnév-előtag) | Rövid leírás |
|---|---|---|
| 1 | `<app>` | `<mit csinál>` |
| 2 | | |

## 5. Hozzáférés *

A felsorolt személyeket a jogosultsági szintnek megfelelő Entra ID-csoportba veszem fel. A jogosultságot a csoport kapja, nem a személy.

| Entra ID e-mail-cím | Jogosultság (Írás / Olvasás) |
|---|---|
| `<név@ceg.hu>` | `Írás` |
| | |

> Írás → `<projekt>-<env>-developers` csoport (Azure Kubernetes Service RBAC Writer).
> Olvasás → `<projekt>-<env>-readers` csoport (Azure Kubernetes Service RBAC Reader).
> Mindkét csoport megkapja az Azure Kubernetes Service Cluster User Role szerepkört is, a kubeconfig letöltéséhez.

## 6. Erőforrásméret *

- [ ] Alapértelmezett: 1 node, 2 vCPU, 8 GiB RAM (`Standard_D2as_v5`)
- [ ] Egyedi méret. Indoklás: `<miért kevés az alapértelmezett, mekkora kellene>`

## 7. Szükséges platformképességek

- [x] HTTPS ingress (Traefik)
- [x] Automatikus DNS-név (External DNS)
- [x] Automatikus TLS-tanúsítvány (cert-manager, Let's Encrypt staging)

## 8. Időzítés

| Mező | Érték |
|---|---|
| Mikorra van rá szükség? * | `<ÉÉÉÉ-HH-NN>` |
| Lejárat * (legfeljebb 3 hónap, hosszabbítható) | `<ÉÉÉÉ-HH-NN>` |

## 9. Megjegyzés

`<bármi, amit még tudnom kell>`

---

## Platform engineer tölti ki

| Mező | Érték |
|---|---|
| Beérkezés dátuma | |
| Döntés (jóváhagyva / elutasítva / kérdés) | |
| Kvóta ellenőrizve (DASv5 / régiós vCPU) | |
| Terraform-könyvtár (`terraform/<env>`) és state kulcs | |
| Tagok object ID-i a `terraform.tfvars`-ban (developers / readers) | |
| `terraform apply` dátuma, commit | |
| DNS-zóna | |
| Traefik EXTERNAL-IP | |
| Segédscript-kimenet csatolva (`kimenetek/`) | |
| Átadás dátuma | |
| Megszüntetés dátuma (`terraform destroy`) | |
```

---

## B. függelék – Segédscript

Az ellenőrzéshez és a beadandó listákhoz használt oktatói segédscript (`segedscript/3-iac-7-homework.sh`), változtatás nélkül. A futtatásának módját a 4.7 írja le.

```bash
#!/bin/bash

az group list -o table
az aks list -o table
az network vnet list --resource-group project-x-sbx-aks-nodes -o table
az network dns zone list

# A bejegyzett DNS nevek listája
az network dns record-set list --resource-group project-x-sbx-dns --zone-name <domain> -o table

# Kubernetesen belüli erőforrások listája és státusza
kubectl get -A pods,ingress,ClusterIssuer,secrets,namespace

# Managed identity és federated credential
az identity list -o table
az identity federated-credential list --resource-group project-x-sbx-aks --identity-name project-x-hw-externaldns -o table

# Group and role assignment
az ad group list -o table
az role assignment list --all -o table

# Tarraform
terraform state list
```

---

## C. függelék – A segédscript és a végpont kimenetei

A kimeneteket a `./scripts/kimenetek-beillesztese.sh` illeszti be változtatás nélkül, a létrehozó scriptek futása után.

### C.1 `project-x-sbx` – segédscript

<!-- KIMENET:segedscript-kimenet-sbx.txt -->
```
Name                     Location       Status
-----------------------  -------------  ---------
azure-signup-rg          eastus         Succeeded
course-baseline          swedencentral  Succeeded
NetworkWatcherRG         swedencentral  Succeeded
project-x-sbx-aks        swedencentral  Succeeded
project-x-sbx-dns        swedencentral  Succeeded
project-x-sbx-aks-nodes  swedencentral  Succeeded
Name           Location       ResourceGroup      KubernetesVersion    CurrentKubernetesVersion    ProvisioningState    Fqdn
-------------  -------------  -----------------  -------------------  --------------------------  -------------------  ------------------------------------------------------
project-x-sbx  swedencentral  project-x-sbx-aks  1.36.3               1.36.3                      Succeeded            project-x-sbx-dns-oh1ja1vx.hcp.swedencentral.azmk8s.io

[
  {
    "etag": "77f79121-66ee-4cf4-ad20-4d9909197616",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Network/dnszones/vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-05.azure-dns.com.",
      "ns2-05.azure-dns.net.",
      "ns3-05.azure-dns.org.",
      "ns4-05.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "course-baseline",
    "tags": {},
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  },
  {
    "etag": "4f23eb65-0510-4d53-9dd9-b9c6d2271e45",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnszones/project-x.sbx.vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "project-x.sbx.vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-09.azure-dns.com.",
      "ns2-09.azure-dns.net.",
      "ns3-09.azure-dns.org.",
      "ns4-09.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "project-x-sbx-dns",
    "tags": {
      "environment": "sbx",
      "expires": "2027-02-09",
      "managed_by": "terraform",
      "owner": "platformengineer@vighsandor.hu",
      "project": "project-x"
    },
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  }
]
TTL     Fqdn                                               Name      ProvisioningState    ResourceGroup
------  -------------------------------------------------  --------  -------------------  -----------------
172800  project-x.sbx.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-sbx-dns
3600    project-x.sbx.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-sbx-dns
300     a-colors.project-x.sbx.vighsandor.az.cubix-pe.hu.  a-colors  Succeeded            project-x-sbx-dns
300     colors.project-x.sbx.vighsandor.az.cubix-pe.hu.    colors    Succeeded            project-x-sbx-dns
NAMESPACE            NAME                                                       READY   STATUS    RESTARTS        AGE
cert-manager         pod/cert-manager-687c8dcfbb-2vq2r                          1/1     Running   0               96s
cert-manager         pod/cert-manager-cainjector-5bfdf76ddd-slkzj               1/1     Running   0               96s
cert-manager         pod/cert-manager-webhook-578b8cbb44-rhpxq                  1/1     Running   0               96s
colors               pod/colors-colors-demo-app-5ffff85675-dddkp                1/1     Running   0               63s
external-dns         pod/external-dns-6cc8b86d8-qrrxd                           1/1     Running   0               2m
ingress-controller   pod/traefik-68895f75cb-qhl4n                               1/1     Running   0               2m31s
kube-system          pod/azure-cns-6rwq5                                        2/2     Running   0               4m18s
kube-system          pod/azure-ip-masq-agent-54dlw                              1/1     Running   0               4m18s
kube-system          pod/azure-wi-webhook-controller-manager-58db98bffb-w685h   1/1     Running   1 (3m29s ago)   4m37s
kube-system          pod/azure-wi-webhook-controller-manager-58db98bffb-zbwcr   1/1     Running   1 (3m24s ago)   4m37s
kube-system          pod/cloud-node-manager-fzm42                               1/1     Running   0               4m18s
kube-system          pod/coredns-5bf45f87d-wgvq5                                1/1     Running   0               4m37s
kube-system          pod/coredns-5bf45f87d-x2h9v                                1/1     Running   0               3m34s
kube-system          pod/coredns-autoscaler-7467554f77-q5qnk                    1/1     Running   0               4m37s
kube-system          pod/csi-azuredisk-node-zvwcz                               3/3     Running   0               4m18s
kube-system          pod/csi-azurefile-node-xbtzj                               4/4     Running   0               4m18s
kube-system          pod/konnectivity-agent-5854c8f68c-bx2d9                    1/1     Running   0               4m34s
kube-system          pod/konnectivity-agent-5854c8f68c-cvtr9                    1/1     Running   0               3m34s
kube-system          pod/konnectivity-agent-autoscaler-5b658f6697-984jx         1/1     Running   0               4m34s
kube-system          pod/kube-proxy-tqbc6                                       1/1     Running   0               4m18s
kube-system          pod/metrics-server-dff79fd46-99r24                         2/2     Running   0               3m17s
kube-system          pod/metrics-server-dff79fd46-cv7g9                         2/2     Running   0               3m17s

NAMESPACE   NAME                                               CLASS     HOSTS                                            ADDRESS          PORTS     AGE
colors      ingress.networking.k8s.io/colors-colors-demo-app   traefik   colors.project-x.sbx.vighsandor.az.cubix-pe.hu   172.130.16.222   80, 443   63s

NAMESPACE   NAME                                        READY   AGE
            clusterissuer.cert-manager.io/letsencrypt   True    68s

NAMESPACE            NAME                                                            TYPE                            DATA   AGE
cert-manager         secret/cert-manager-webhook-ca                                  Opaque                          3      91s
cert-manager         secret/letsencrypt-account-key                                  Opaque                          1      69s
cert-manager         secret/sh.helm.release.v1.cert-manager.v1                       helm.sh/release.v1              1      100s
colors               secret/blue-tls                                                 kubernetes.io/tls               2      10s
colors               secret/sh.helm.release.v1.colors.v1                             helm.sh/release.v1              1      64s
external-dns         secret/external-dns                                             Opaque                          1      2m2s
external-dns         secret/sh.helm.release.v1.external-dns.v1                       helm.sh/release.v1              1      2m3s
ingress-controller   secret/sh.helm.release.v1.traefik.v1                            helm.sh/release.v1              1      2m34s
kube-system          secret/azure-wi-webhook-server-cert                             Opaque                          3      5m53s
kube-system          secret/bootstrap-token-rsffxs                                   bootstrap.kubernetes.io/token   4      5m40s
kube-system          secret/konnectivity-certs                                       Opaque                          3      4m35s
kube-system          secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v4   helm.sh/release.v1              1      2m29s
kube-system          secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v5   helm.sh/release.v1              1      24s
kube-system          secret/sh.helm.release.v1.aks-managed-workload-identity.v2      helm.sh/release.v1              1      3m33s
kube-system          secret/sh.helm.release.v1.aks-managed-workload-identity.v3      helm.sh/release.v1              1      113s

NAMESPACE   NAME                           STATUS   AGE
            namespace/cert-manager         Active   100s
            namespace/colors               Active   65s
            namespace/default              Active   6m15s
            namespace/external-dns         Active   2m3s
            namespace/ingress-controller   Active   2m35s
            namespace/kube-node-lease      Active   6m15s
            namespace/kube-public          Active   6m15s
            namespace/kube-system          Active   6m15s
ClientId                              IsolationScope    Location       Name                       PrincipalId                           ResourceGroup            TenantId
------------------------------------  ----------------  -------------  -------------------------  ------------------------------------  -----------------------  ------------------------------------
35c90641-7ded-4d2d-8974-3e841b526156  None              swedencentral  project-x-sbx-aks          420013ba-7f4a-48cb-bf05-668a669c6c8d  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
3e203fbd-4a47-43a0-9919-8fbe5437cf32  None              swedencentral  project-x-sbx-externaldns  d086277a-33a7-47ad-bc70-ff1b06ac6ac8  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
0d2b4508-25fc-4d3f-b717-d98b4a34665c  None              swedencentral  project-x-sbx-agentpool    aeb94da5-b4cd-4a32-b48f-47c7b09c6df4  project-x-sbx-aks-nodes  c9b482b1-d17b-430e-bbe6-5d64ba800aa1
Issuer                                                                                                                   Name          ResourceGroup      Subject
-----------------------------------------------------------------------------------------------------------------------  ------------  -----------------  -----------------------------------------------
https://swedencentral.oic.prod-aks.azure.com/c9b482b1-d17b-430e-bbe6-5d64ba800aa1/8db7a424-c2cc-487b-bda4-49a81bcafa92/  external-dns  project-x-sbx-aks  system:serviceaccount:external-dns:external-dns
CreatedDateTime       Description                                DisplayName                    IsAssignableToRole    MailEnabled    MailNickname    RenewedDateTime       SecurityEnabled    SecurityIdentifier
--------------------  -----------------------------------------  -----------------------------  --------------------  -------------  --------------  --------------------  -----------------  --------------------------------------------------
2026-11-09T15:42:28Z  project-x sbx környezet fejlesztői (írás)  project-x-sbx-developers       False                 False          01d98f81-9      2026-11-09T15:42:28Z  True               S-1-12-1-86427182-1204094678-1165799335-3560982494
2026-11-09T15:42:28Z  project-x sbx környezet platformadminjai   project-x-sbx-platform-admins  False                 False          a4355f88-b      2026-11-09T15:42:28Z  True               S-1-12-1-1803399906-1219421779-371626414-465318757
Principal                                                                       Role                                         Scope
------------------------------------------------------------------------------  -------------------------------------------  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Owner                                        /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Storage Blob Data Contributor                /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Storage/storageAccounts/platencbvighsandor
3e203fbd-4a47-43a0-9919-8fbe5437cf32                                            DNS Zone Contributor                         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnsZones/project-x.sbx.vighsandor.az.cubix-pe.hu
35c90641-7ded-4d2d-8974-3e841b526156                                            Network Contributor                          /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.Network/virtualNetworks/project-x-sbx-network/subnets/project-x-sbx-aks-nodes
35c90641-7ded-4d2d-8974-3e841b526156                                            Contributor                                  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks-nodes
project-x-sbx-developers                                                        Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-developers                                                        Azure Kubernetes Service RBAC Writer         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
data.azurerm_client_config.current
data.azurerm_dns_zone.parent
azuread_group.developers
azuread_group.platform_admins
azuread_group_member.platform_admins["2477da76-ba77-4008-8ac9-9bda97840fa2"]
azurerm_dns_ns_record.delegation
azurerm_dns_zone.env
azurerm_federated_identity_credential.external_dns
azurerm_kubernetes_cluster.aks
azurerm_resource_group.aks
azurerm_resource_group.dns
azurerm_role_assignment.aks["developers-cluster_user"]
azurerm_role_assignment.aks["developers-writer"]
azurerm_role_assignment.aks["platform_admins-cluster_admin"]
azurerm_role_assignment.aks["platform_admins-cluster_user"]
azurerm_role_assignment.aks_subnet_network_contributor
azurerm_role_assignment.external_dns_zone_contributor
azurerm_subnet.aks_nodes
azurerm_user_assigned_identity.aks
azurerm_user_assigned_identity.external_dns
azurerm_virtual_network.aks
```
<!-- /KIMENET -->

### C.2 `project-x-sbx` – curl

<!-- KIMENET:curl-sbx.txt -->
```
$ curl -sk https://colors.project-x.sbx.vighsandor.az.cubix-pe.hu
<!DOCTYPE html>
<html>
  <head>
    <title>Rollouts Demo</title>
    <link rel="stylesheet" href="style.css" type="text/css" />
  </head>
  <body>
    <div class="header spread">
        <img src="logo.png" class="logo" />
        <h1>ARGO ROLLOUTS <span class="orange">DEMO</span></h1>
        <div class="flex">
          <div class="button button--resize" id="resize">FIT</div>
        </div>
    </div>
    <div class="controls">
      <div class="control spread">
        <div>COLOR</div>
        <div class="colors" id="colors"></div>
      </div>
      <div class="control spread">
        <div class="button button--start">START</div>
        <div class="button button--stop">STOP</div>
      </div>
      <div class="control">
        <div class="control spread">
          <div>LATENCY</div>
          <div class="white" id="latency-label">0.0s</div>
        </div>
        <input type="range" min="0" max="5" value="0" class="slider" id="latency" step="0.1">
      </div>
      <div class="control">
        <div class="control spread">
          <div>ERROR</div>
          <div class="white" id="error-label">0.0s</div>
        </div>
        <input type="range" min="0" max="100" value="0" class="slider" id="error" step="1">
      </div>
    </div>
    <div id="grid" class="grid"></div>
    <div id="graph" class="graph"></div>
  </body>
  <script src="main.js"></script>
</html>
```
<!-- /KIMENET -->

### C.3 `project-x-dev` – segédscript

<!-- KIMENET:segedscript-kimenet-dev.txt -->
```
Name                     Location       Status
-----------------------  -------------  ---------
azure-signup-rg          eastus         Succeeded
course-baseline          swedencentral  Succeeded
NetworkWatcherRG         swedencentral  Succeeded
project-x-sbx-aks        swedencentral  Succeeded
project-x-sbx-dns        swedencentral  Succeeded
project-x-sbx-aks-nodes  swedencentral  Succeeded
project-x-dev-aks        swedencentral  Succeeded
project-x-dev-dns        swedencentral  Succeeded
project-x-dev-aks-nodes  swedencentral  Succeeded
Name           Location       ResourceGroup      KubernetesVersion    CurrentKubernetesVersion    ProvisioningState    Fqdn
-------------  -------------  -----------------  -------------------  --------------------------  -------------------  ------------------------------------------------------
project-x-sbx  swedencentral  project-x-sbx-aks  1.36.3               1.36.3                      Succeeded            project-x-sbx-dns-oh1ja1vx.hcp.swedencentral.azmk8s.io
project-x-dev  swedencentral  project-x-dev-aks  1.36.3               1.36.3                      Succeeded            project-x-dev-dns-oi5ixgan.hcp.swedencentral.azmk8s.io

[
  {
    "etag": "77f79121-66ee-4cf4-ad20-4d9909197616",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Network/dnszones/vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-05.azure-dns.com.",
      "ns2-05.azure-dns.net.",
      "ns3-05.azure-dns.org.",
      "ns4-05.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "course-baseline",
    "tags": {},
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  },
  {
    "etag": "70e6a005-d9dc-4713-87c4-39ea95e520ef",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-dns/providers/Microsoft.Network/dnszones/project-x.dev.vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "project-x.dev.vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-08.azure-dns.com.",
      "ns2-08.azure-dns.net.",
      "ns3-08.azure-dns.org.",
      "ns4-08.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "project-x-dev-dns",
    "tags": {
      "environment": "dev",
      "expires": "2027-02-09",
      "managed_by": "terraform",
      "owner": "platformengineer@vighsandor.hu",
      "project": "project-x"
    },
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  },
  {
    "etag": "4f23eb65-0510-4d53-9dd9-b9c6d2271e45",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnszones/project-x.sbx.vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "project-x.sbx.vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-09.azure-dns.com.",
      "ns2-09.azure-dns.net.",
      "ns3-09.azure-dns.org.",
      "ns4-09.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "project-x-sbx-dns",
    "tags": {
      "environment": "sbx",
      "expires": "2027-02-09",
      "managed_by": "terraform",
      "owner": "platformengineer@vighsandor.hu",
      "project": "project-x"
    },
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  }
]
TTL     Fqdn                                               Name      ProvisioningState    ResourceGroup
------  -------------------------------------------------  --------  -------------------  -----------------
172800  project-x.dev.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-dev-dns
3600    project-x.dev.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-dev-dns
300     a-colors.project-x.dev.vighsandor.az.cubix-pe.hu.  a-colors  Succeeded            project-x-dev-dns
300     colors.project-x.dev.vighsandor.az.cubix-pe.hu.    colors    Succeeded            project-x-dev-dns
NAMESPACE            NAME                                                     READY   STATUS    RESTARTS      AGE
cert-manager         pod/cert-manager-687c8dcfbb-lvpd5                        1/1     Running   0             94s
cert-manager         pod/cert-manager-cainjector-5bfdf76ddd-64wdn             1/1     Running   0             94s
cert-manager         pod/cert-manager-webhook-578b8cbb44-wzjpl                1/1     Running   0             94s
colors               pod/colors-colors-demo-app-5ffff85675-4jzvl              1/1     Running   0             66s
external-dns         pod/external-dns-6d6975cf79-tz4z9                        1/1     Running   0             119s
ingress-controller   pod/traefik-68895f75cb-crz2s                             1/1     Running   0             2m28s
kube-system          pod/azure-cns-z65l2                                      2/2     Running   0             21m
kube-system          pod/azure-ip-masq-agent-ct8wv                            1/1     Running   0             21m
kube-system          pod/azure-wi-webhook-controller-manager-bd689794-bvtwl   1/1     Running   1 (20m ago)   21m
kube-system          pod/azure-wi-webhook-controller-manager-bd689794-ntsmm   1/1     Running   1 (20m ago)   21m
kube-system          pod/cloud-node-manager-j5m4d                             1/1     Running   0             21m
kube-system          pod/coredns-5bf45f87d-l97mx                              1/1     Running   0             20m
kube-system          pod/coredns-5bf45f87d-p24k8                              1/1     Running   0             21m
kube-system          pod/coredns-autoscaler-7467554f77-mkhx2                  1/1     Running   0             21m
kube-system          pod/csi-azuredisk-node-wm895                             3/3     Running   0             21m
kube-system          pod/csi-azurefile-node-88rxz                             4/4     Running   0             21m
kube-system          pod/konnectivity-agent-autoscaler-5b658f6697-cjbrc       1/1     Running   0             21m
kube-system          pod/konnectivity-agent-c786bd659-8jn46                   1/1     Running   0             21m
kube-system          pod/konnectivity-agent-c786bd659-v48xc                   1/1     Running   0             20m
kube-system          pod/kube-proxy-25597                                     1/1     Running   0             21m
kube-system          pod/metrics-server-dff79fd46-8qwrd                       2/2     Running   0             20m
kube-system          pod/metrics-server-dff79fd46-qltsf                       2/2     Running   0             20m

NAMESPACE   NAME                                               CLASS     HOSTS                                            ADDRESS          PORTS     AGE
colors      ingress.networking.k8s.io/colors-colors-demo-app   traefik   colors.project-x.dev.vighsandor.az.cubix-pe.hu   74.241.212.140   80, 443   67s

NAMESPACE   NAME                                        READY   AGE
            clusterissuer.cert-manager.io/letsencrypt   True    71s

NAMESPACE            NAME                                                             TYPE                            DATA   AGE
cert-manager         secret/cert-manager-webhook-ca                                   Opaque                          3      91s
cert-manager         secret/letsencrypt-account-key                                   Opaque                          1      71s
cert-manager         secret/sh.helm.release.v1.cert-manager.v1                        helm.sh/release.v1              1      98s
colors               secret/blue-tls                                                  kubernetes.io/tls               2      10s
colors               secret/sh.helm.release.v1.colors.v1                              helm.sh/release.v1              1      67s
external-dns         secret/external-dns                                              Opaque                          1      2m1s
external-dns         secret/sh.helm.release.v1.external-dns.v1                        helm.sh/release.v1              1      2m1s
ingress-controller   secret/sh.helm.release.v1.traefik.v1                             helm.sh/release.v1              1      2m31s
kube-system          secret/azure-wi-webhook-server-cert                              Opaque                          3      23m
kube-system          secret/bootstrap-token-3is5wl                                    bootstrap.kubernetes.io/token   4      23m
kube-system          secret/konnectivity-certs                                        Opaque                          3      21m
kube-system          secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v12   helm.sh/release.v1              1      2m59s
kube-system          secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v13   helm.sh/release.v1              1      53s
kube-system          secret/sh.helm.release.v1.aks-managed-workload-identity.v11      helm.sh/release.v1              1      2m26s
kube-system          secret/sh.helm.release.v1.aks-managed-workload-identity.v12      helm.sh/release.v1              1      18s

NAMESPACE   NAME                           STATUS   AGE
            namespace/cert-manager         Active   99s
            namespace/colors               Active   68s
            namespace/default              Active   24m
            namespace/external-dns         Active   2m1s
            namespace/ingress-controller   Active   2m32s
            namespace/kube-node-lease      Active   24m
            namespace/kube-public          Active   24m
            namespace/kube-system          Active   24m
ClientId                              IsolationScope    Location       Name                       PrincipalId                           ResourceGroup            TenantId
------------------------------------  ----------------  -------------  -------------------------  ------------------------------------  -----------------------  ------------------------------------
35c90641-7ded-4d2d-8974-3e841b526156  None              swedencentral  project-x-sbx-aks          420013ba-7f4a-48cb-bf05-668a669c6c8d  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
3e203fbd-4a47-43a0-9919-8fbe5437cf32  None              swedencentral  project-x-sbx-externaldns  d086277a-33a7-47ad-bc70-ff1b06ac6ac8  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
0d2b4508-25fc-4d3f-b717-d98b4a34665c  None              swedencentral  project-x-sbx-agentpool    aeb94da5-b4cd-4a32-b48f-47c7b09c6df4  project-x-sbx-aks-nodes  c9b482b1-d17b-430e-bbe6-5d64ba800aa1
de709159-3478-4e02-88a9-1b516a1f669d  None              swedencentral  project-x-dev-aks          11b6d0a6-17f0-4241-a8ce-a9d5e366238b  project-x-dev-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
9b00496c-b4b4-403c-9a32-43a45d878f5f  None              swedencentral  project-x-dev-externaldns  c2758c6d-8863-4dd0-a8ef-bd1e106f1e11  project-x-dev-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
9e2a67e7-1f0d-4d24-9eba-bee92cfd32ae  None              swedencentral  project-x-dev-agentpool    802633d8-e226-4891-b16a-b3fd844bc5eb  project-x-dev-aks-nodes  c9b482b1-d17b-430e-bbe6-5d64ba800aa1
Issuer                                                                                                                   Name          ResourceGroup      Subject
-----------------------------------------------------------------------------------------------------------------------  ------------  -----------------  -----------------------------------------------
https://swedencentral.oic.prod-aks.azure.com/c9b482b1-d17b-430e-bbe6-5d64ba800aa1/4ec9e5b2-d21f-42a4-9804-c3a9a0772290/  external-dns  project-x-dev-aks  system:serviceaccount:external-dns:external-dns
CreatedDateTime       Description                                DisplayName                    IsAssignableToRole    MailEnabled    MailNickname    RenewedDateTime       SecurityEnabled    SecurityIdentifier
--------------------  -----------------------------------------  -----------------------------  --------------------  -------------  --------------  --------------------  -----------------  ----------------------------------------------------
2026-11-09T15:42:28Z  project-x sbx környezet fejlesztői (írás)  project-x-sbx-developers       False                 False          01d98f81-9      2026-11-09T15:42:28Z  True               S-1-12-1-86427182-1204094678-1165799335-3560982494
2026-11-09T15:42:28Z  project-x sbx környezet platformadminjai   project-x-sbx-platform-admins  False                 False          a4355f88-b      2026-11-09T15:42:28Z  True               S-1-12-1-1803399906-1219421779-371626414-465318757
2026-11-09T15:53:18Z  project-x dev környezet fejlesztői (írás)  project-x-dev-developers       False                 False          5d052b26-d      2026-11-09T15:53:18Z  True               S-1-12-1-2073888591-1300772916-3077791149-591231089
2026-11-09T15:53:17Z  project-x dev környezet platformadminjai   project-x-dev-platform-admins  False                 False          db190256-f      2026-11-09T15:53:17Z  True               S-1-12-1-3475882151-1195152490-3267294895-1156141564
Principal                                                                       Role                                         Scope
------------------------------------------------------------------------------  -------------------------------------------  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Owner                                        /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Storage Blob Data Contributor                /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Storage/storageAccounts/platencbvighsandor
3e203fbd-4a47-43a0-9919-8fbe5437cf32                                            DNS Zone Contributor                         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnsZones/project-x.sbx.vighsandor.az.cubix-pe.hu
35c90641-7ded-4d2d-8974-3e841b526156                                            Network Contributor                          /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.Network/virtualNetworks/project-x-sbx-network/subnets/project-x-sbx-aks-nodes
35c90641-7ded-4d2d-8974-3e841b526156                                            Contributor                                  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks-nodes
project-x-sbx-developers                                                        Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-developers                                                        Azure Kubernetes Service RBAC Writer         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
de709159-3478-4e02-88a9-1b516a1f669d                                            Network Contributor                          /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.Network/virtualNetworks/project-x-dev-network/subnets/project-x-dev-aks-nodes
9b00496c-b4b4-403c-9a32-43a45d878f5f                                            DNS Zone Contributor                         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-dns/providers/Microsoft.Network/dnsZones/project-x.dev.vighsandor.az.cubix-pe.hu
de709159-3478-4e02-88a9-1b516a1f669d                                            Contributor                                  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks-nodes
project-x-dev-developers                                                        Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-platform-admins                                                   Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-developers                                                        Azure Kubernetes Service RBAC Writer         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-platform-admins                                                   Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
data.azurerm_client_config.current
data.azurerm_dns_zone.parent
azuread_group.developers
azuread_group.platform_admins
azuread_group_member.platform_admins["2477da76-ba77-4008-8ac9-9bda97840fa2"]
azurerm_dns_ns_record.delegation
azurerm_dns_zone.env
azurerm_federated_identity_credential.external_dns
azurerm_kubernetes_cluster.aks
azurerm_resource_group.aks
azurerm_resource_group.dns
azurerm_role_assignment.aks["developers-cluster_user"]
azurerm_role_assignment.aks["developers-writer"]
azurerm_role_assignment.aks["platform_admins-cluster_admin"]
azurerm_role_assignment.aks["platform_admins-cluster_user"]
azurerm_role_assignment.aks_subnet_network_contributor
azurerm_role_assignment.external_dns_zone_contributor
azurerm_subnet.aks_nodes
azurerm_user_assigned_identity.aks
azurerm_user_assigned_identity.external_dns
azurerm_virtual_network.aks
```
<!-- /KIMENET -->

### C.4 `project-x-dev` – curl

<!-- KIMENET:curl-dev.txt -->
```
$ curl -sk https://colors.project-x.dev.vighsandor.az.cubix-pe.hu
(nincs válasz – DNS-gyorsítótár? Próbáld újra pár perc múlva.)
```
A hibát még nem találtam meg de a cluster elemeii futnak, így nem ott keresem:

```
kubectl get po -A
NAMESPACE            NAME                                                 READY   STATUS    RESTARTS      AGE
cert-manager         cert-manager-687c8dcfbb-lvpd5                        1/1     Running   0             8m12s
cert-manager         cert-manager-cainjector-5bfdf76ddd-64wdn             1/1     Running   0             8m12s
cert-manager         cert-manager-webhook-578b8cbb44-wzjpl                1/1     Running   0             8m12s
colors               colors-colors-demo-app-5ffff85675-4jzvl              1/1     Running   0             7m44s
external-dns         external-dns-6d6975cf79-tz4z9                        1/1     Running   0             8m37s
ingress-controller   traefik-68895f75cb-crz2s                             1/1     Running   0             9m6s
kube-system          azure-cns-z65l2                                      2/2     Running   0             28m
kube-system          azure-ip-masq-agent-ct8wv                            1/1     Running   0             28m
kube-system          azure-wi-webhook-controller-manager-bd689794-bvtwl   1/1     Running   1 (27m ago)   28m
kube-system          azure-wi-webhook-controller-manager-bd689794-ntsmm   1/1     Running   1 (27m ago)   28m
kube-system          cloud-node-manager-j5m4d                             1/1     Running   0             28m
kube-system          coredns-5bf45f87d-l97mx                              1/1     Running   0             27m
kube-system          coredns-5bf45f87d-p24k8                              1/1     Running   0             28m
kube-system          coredns-autoscaler-7467554f77-mkhx2                  1/1     Running   0             28m
kube-system          csi-azuredisk-node-wm895                             3/3     Running   0             28m
kube-system          csi-azurefile-node-88rxz                             4/4     Running   0             28m
kube-system          konnectivity-agent-5f9946665-552gm                   1/1     Running   0             92s
kube-system          konnectivity-agent-5f9946665-57lp6                   1/1     Running   0             93s
kube-system          konnectivity-agent-autoscaler-5b658f6697-cjbrc       1/1     Running   0             28m
kube-system          kube-proxy-25597                                     1/1     Running   0             28m
kube-system          metrics-server-dff79fd46-8qwrd                       2/2     Running   0             27m
kube-system          metrics-server-dff79fd46-qltsf                       2/2     Running   0             27m

kubectl get ingress -A
NAMESPACE   NAME                     CLASS     HOSTS                                            ADDRESS          PORTS     AGE
colors      colors-colors-demo-app   traefik   colors.project-x.dev.vighsandor.az.cubix-pe.hu   74.241.212.140   80, 443   8m3s
```

<!-- /KIMENET -->
