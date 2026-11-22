# Környezetigénylési folyamat – Project X miniplatform (pipeline + Terraform + Argo CD)

Ebben a dokumentumban leírom, hogyan működik nálam az új futtatókörnyezetek igénylése és kiszolgálása. Két nézőpontot rögzítek:

1. **A fejlesztői oldal:** mit kell tennie egy fejlesztőnek, ha új környezetet szeretne kapni (3. fejezet).
2. **Az üzemeltetői oldal:** mit csinálok én platform engineerként, amikor beérkezik egy igénylés (4. fejezet).

A folyamat alapja a `project-x` **sandbox** (`sbx`) és **dev** környezet. Ezeket először kézzel (ClickOps) építettem fel, aztán Terraform-kódba ültettem át, a 4.0-s verzióban pedig **a kód már csak GitHub Actions pipeline-ból fut**. Az 5.0-s verziótól a Kubernetesen belüli komponenseket **Argo CD** telepíti és tartja folyamatosan a kívánt állapotban. Egy környezet igénylése ma egy **pull request**: a fejlesztő leírja a kívánt környezetet, a pipeline megmutatja, mi fog történni, és a merge után létre is hozza.

**Az alap DNS-zónám:** `vighsandor.az.cubix-pe.hu`. Minden környezet ez alá kap saját alzónát.

**A repó:** <https://github.com/vighsandor/cubixplatformeng>. A fő ág a `platformeng-w3`. Az 5. heti állapot tagje `week5-argocd-basics`, a 4. hetié `week4-pipeline-tf`.

### Változásnapló

| Verzió | Tartalom |
|---|---|
| 1.0 | ClickOps-alapinfrastruktúra: AKS, Traefik, Azure DNS alzóna kézi A rekordokkal, cert-manager, Let's Encrypt |
| 2.0 | Entra ID-integráció és automatikus DNS: jogosultság csak Entra ID-csoportoknak; External DNS managed identityvel és workload identity federationnel, titok nélkül |
| 3.0 | Infrastructure as Code: az Azure- és Entra ID-erőforrások Terraformból, környezetenként külön kódkönyvtárban és state-tel; a Kubernetesen belüli rész még kézi Helm |
| **4.0** | **Pipeline és teljes IaC.** A Terraform GitHub Actionsből fut (pull requestre `fmt` + `validate` + `plan`, a fő ágra merge után `apply`), a GitHub titok nélkül, workload identity federationnel jelentkezik be az Azure-ba. A fő ágat ruleset védi. **A környezetigénylés egy pull request** (3. fejezet). A Kubernetesen belüli komponenseket (Traefik, External DNS, cert-manager, ClusterIssuer, demóalkalmazás) is a Terraform telepíti. Egy kód, több környezet: **Terraform workspace-ek** és környezetenkénti `tfvars`, workspace-védelemmel. Az Entra ID-csoportok külön fájlba kerültek, a tagokat név és UPN alapján adom meg (a Terraform keresi ki az object ID-t), és magam is tagja vagyok minden csoportnak, hogy a jogosultságok működés közben is látszódjanak. |
| **5.0** | **Argo CD (GitOps-alapok).** A Terraform közvetlenül már csak az Argo CD-t telepíti (Helm). A platformkomponensek (Traefik, External DNS, cert-manager, ClusterIssuer) és a demóalkalmazás **Argo CD Application-ök**, amelyeket a Terraform hoz létre a `bedag/raw` charttal. Két Argo CD-projekt: **platform** (közös infrastruktúra) és **product** (a fejlesztők alkalmazásai). Minden Application **AutoSync** (prune + selfHeal) és **finalizer** beállítással fut, és Terraform-szinten az Argo CD-től és a projektektől függ. Az Argo CD-be **Entra ID-fiókkal** lehet belépni (OIDC, titok nélkül, workload identityvel), a jogosultságot a környezet Entra ID-csoportjai adják; a helyi admin fiók ki van kapcsolva. **A 4. heti visszajelzések alapján:** nincs külön igénylőlap, az igénylés minden adata (igénylő, csapat, indoklás, jóváhagyó) a környezet `tfvars` fájljának `request` blokkjába került, a Terraform ellenőrzi és a state-ben is rögzíti (`terraform_data.request`); merge után **először csak a sandbox** frissül, a többi környezet csak annak sikere után és **kézi jóváhagyással** (GitHub environment: `promotion`). |

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
| Folyamatos telepítés (CD) | Argo CD: `https://argocd.<projekt>.<env>.vighsandor.az.cubix-pe.hu`. Folyamatosan összeveti a kívánt és a valós állapotot, az eltérést (drift) megmutatja és automatikusan visszaállítja. A fejlesztők a **product** projektben saját alkalmazást is telepíthetnek vele. |
| Bejelentkezés az Argo CD-be | Entra ID-fiókkal (*LOG IN VIA ENTRA ID*), a jog a környezet csoportjaiból jön; jelszót nem kell kimásolni egyetlen secretből sem |
| Gépi identitás | Workload identity federation: a clusterben futó platformkomponensek (External DNS, Argo CD), és a pipeline is titkos kulcs nélkül érik el az Azure-t és az Entra ID-t |
| Önkiszolgálás | Környezetet pull requesttel lehet igényelni; a pipeline a merge után emberi kattintgatás nélkül felépíti |
| Reprodukálhatóság | Minden környezet ugyanabból a Terraform-kódból jön létre; két környezet között csak a `tfvars` fájl és a workspace különbözik |

Az eredmény: a fejlesztő egyetlen Ingress-erőforrással **névvel elérhető, TLS-sel védett** végpontot kap, emberi beavatkozás nélkül, az alkalmazását pedig az Argo CD folyamatosan a kívánt állapotban tartja.

### 1.2 Megkötések és a mögöttük álló döntéseim

| Terület | Szabály | Indoklás |
|---|---|---|
| Régió | Sweden Central | Itt van biztosított kvótám, és minden környezet egy helyen fut. |
| Méret | 1 node, `Standard_D2as_v5` (2 vCPU, 8 GiB RAM) | A kvóta szűkös: a Standard DASv5 családra 4 vCPU, a régióra összesen 8 vCPU jut. Nagyobb gépet csak indoklással adok. |
| Frissítés | Az automatikus frissítés ki van kapcsolva | Rövid életű, eltakarítandó környezetekről van szó; a verziót én tartom kézben (Terraform-változó). |
| **Változtatás** | **Minden változás pull requesten keresztül megy, és csak a pipeline módosítja az infrastruktúrát** | A fő ágra közvetlenül senki nem pusholhat (én sem). Minden változáshoz tartozik egy plan, egy review és egy futási napló: visszakövethető, ki, mit, mikor és miért változtatott (auditálhatóság). A portálon kézzel nem módosítok, mert az driftet okoz. |
| **Élesítés sorrendje** | Merge után először csak a sandbox (`sbx`) frissül; a többi környezet csak annak sikere után, kézi jóváhagyással | A `validate` és a `plan` nem szűr ki mindent (pl. egy hibás Helm-érték csak telepítéskor derül ki). Ha valami mégis rossz, a sandboxon látszik először, és nem viszem tovább. |
| Jogosultság | Jogot csak Entra ID-csoport kap, személy soha. Egyetlen kivétel a pipeline gépi identitása (4.3). | Csoportokkal a jogosultságkezelés skálázható és követhető. Ha valaki elhagyja a projektet, elég kivenni a csoportból (egy sor törlése a `tfvars`-ból). |
| Gépi hozzáférés | Titkos kulcsot nem használok; a gépi identitás managed identity, federated credentiallel | A lejáró, kézzel forgatandó titkok kezelése hibalehetőség és biztonsági kockázat. A GitHub repóban nincs Azure-jelszó, csak azonosítók. |
| Legkisebb jogosultság | Az External DNS identitása csak *DNS Zone Contributor* szerepkört kap, és csak a saját környezete alzónáján | Ha egy környezet komponense kompromittálódik, más környezet DNS-éhez akkor sem fér hozzá. |
| DNS | A hosztnevek automatikusan jönnek létre, de csak a környezet saját alzónáján belül | Az External DNS `domainFilters` beállítása a zónán kívüli hosztneveket figyelmen kívül hagyja. |
| TLS | Let's Encrypt **staging** végpont | Az éles Let's Encrypt ugyanarra a névre nagyjából heti 5 tanúsítványt ad ki; a stagingnél ez a korlát jóval magasabb, így szabadon lehet újraépíteni. Ára, hogy a böngésző „nem biztonságos” figyelmeztetést ad. |
| Platformkomponensek | A Traefiket, az External DNS-t, a cert-managert és a ClusterIssuert az Argo CD **platform** projektje kezeli, AutoSync + selfHeal beállítással | Ha valaki kézzel módosít vagy töröl valamit (`kubectl edit`, `kubectl delete`), az Argo CD perceken belül visszaállítja. A platform namespace-eibe a **product** projektből nem lehet telepíteni. |
| Élettartam | A lejárati dátum után megszüntetem a környezetet, ha nem kérik a meghosszabbítását | A nem használt infrastruktúra pénzbe kerül és foglalja a kvótát. A lebontás egy kézzel indítható pipeline (4.8). |

---

## 2. Elnevezési konvenció

Minden erőforrás nevébe beleteszem a **projekt** és a **környezet** jelét, a komponensek nevében pedig a **komponens** nevét is. A Terraform-kódban ezt egyetlen származtatott érték biztosítja: `local.resource_basename = "${var.project_name}-${var.env_name}"`. A nevek így nem gépelhetők el, és két környezet nem ütközhet.

### 2.1 Azure-erőforrások (környezetenként)

| Erőforrás | Minta | `sbx` | `dev` | Terraform-erőforrás |
|---|---|---|---|---|
| Resource group (AKS) | `<projekt>-<env>-aks` | `project-x-sbx-aks` | `project-x-dev-aks` | `azurerm_resource_group.aks` |
| AKS cluster | `<projekt>-<env>` | `project-x-sbx` | `project-x-dev` | `azurerm_kubernetes_cluster.aks` |
| Infrastruktúra (node) resource group | `<projekt>-<env>-aks-nodes` | `project-x-sbx-aks-nodes` | `project-x-dev-aks-nodes` | (az AKS hozza létre) |
| Virtuális hálózat | `<projekt>-<env>-network` | `10.224.0.0/12` | `10.240.0.0/12` | `azurerm_virtual_network.aks` |
| Alhálózat (node-ok) | `<projekt>-<env>-aks-nodes` | `10.224.0.0/24` | `10.240.0.0/24` | `azurerm_subnet.aks_nodes` |
| Managed identity (AKS) | `<projekt>-<env>-aks` | `project-x-sbx-aks` | `project-x-dev-aks` | `azurerm_user_assigned_identity.aks` |
| Managed identity (External DNS) | `<projekt>-<env>-externaldns` | `project-x-sbx-externaldns` | `project-x-dev-externaldns` | `azurerm_user_assigned_identity.external_dns` |
| Federated credential (External DNS) | `external-dns` | `external-dns` | `external-dns` | `azurerm_federated_identity_credential.external_dns` |
| Entra ID-alkalmazás (Argo CD SSO) | `<projekt>-<env>-argocd` | `project-x-sbx-argocd` | `project-x-dev-argocd` | `azuread_application.argocd` (+ service principal, federated credential `argocd-server`) |
| Resource group (DNS) | `<projekt>-<env>-dns` | `project-x-sbx-dns` | `project-x-dev-dns` | `azurerm_resource_group.dns` |
| DNS alzóna | `<projekt>.<env>.vighsandor.az.cubix-pe.hu` | `project-x.sbx.…` | `project-x.dev.…` | `azurerm_dns_zone.env` |
| NS-delegáció a szülőzónában | `<projekt>.<env>` | `project-x.sbx` | `project-x.dev` | `azurerm_dns_ns_record.delegation` |
| Terraform workspace | `<env>` | `sbx` | `dev` | – |
| Terraform state (blob) | `<projekt>.tfstateenv:<env>` | `project-x.tfstateenv:sbx` | `project-x.tfstateenv:dev` | (backend, workspace-enként) |
| Bemenetek | `terraform/environments/<env>.tfvars` | `sbx.tfvars` | `dev.tfvars` | – |

### 2.2 Közös, egyszer létrehozott erőforrások (`course-baseline`)

| Erőforrás | Név | Szerep |
|---|---|---|
| DNS-zóna | `vighsandor.az.cubix-pe.hu` | a szülőzóna; a környezetek ide delegálnak |
| Storage account + container | `platencbvighsandor` / `tfstate` | a Terraform state |
| Managed identity | `github-repos` | **a pipeline identitása** (4.2) |

> Az Argo CD Entra ID-alkalmazása környezetenként külön van, mert a visszahívási cím (`https://argocd.<projekt>.<env>…/auth/callback`) és a workload identity federation (a cluster OIDC-kibocsátója) is környezetfüggő.

### 2.3 Entra ID-csoportok (környezetenként, `entra.tf`)

| Csoport | Minta | Tagok (`tfvars`) | Szerepkörök a clusteren | Argo CD-szerepkör |
|---|---|---|---|---|
| Platformadminok | `<projekt>-<env>-platform-admins` | `platform_admins` (én) + `platform_admin_service_principals` (a pipeline: `github-repos`) | Azure Kubernetes Service **RBAC Cluster Admin**, **Cluster User Role**; a pipeline identitása ezen felül közvetlenül is RBAC Cluster Admin (4.3) | `role:admin` |
| Fejlesztők (írás) | `<projekt>-<env>-developers` | `developers` | Azure Kubernetes Service **RBAC Writer**, **Cluster User Role** | `role:developer`: mindent lát, a **product** projektben alkalmazást hozhat létre, módosíthat, szinkronizálhat, törölhet, és láthatja a logokat |
| Olvasók | `<projekt>-<env>-readers` | `readers` | Azure Kubernetes Service **RBAC Reader**, **Cluster User Role** | `role:readonly` |

Az Argo CD a belépéskor kapott Entra ID-tokenben lévő csoport-azonosítók (`groups` claim) alapján dönt; a csoportok object ID-ját a Terraform írja be az Argo CD RBAC-beállításába (`policy.csv`). Aki egyik csoportnak sem tagja, be tud lépni, de semmit nem lát (`policy.default` üres).

A tagokat **név → UPN** párokkal adom meg (pl. `vighsandor = "…@….onmicrosoft.com"`), az object ID-t a Terraform keresi ki (`data "azuread_user"`). A plan így ember által olvasható nevet mutat (`azuread_group_member.env["developers/vighsandor"]`), és a `tfvars` önmagában is dokumentálja, ki milyen jogot kapott. Magam mindhárom csoportnak tagja vagyok, hogy a jogosultságok működését (írás, olvasás) a saját fiókommal is ellenőrizni tudjam.

### 2.4 Kubernetes-objektumok

**A Terraform közvetlen Helm-telepítései** (`helm_release`, az `argocd` namespace-ben):

| Mit | Helm release | Chart (verzió) |
|---|---|---|
| Argo CD | `argocd` | `argo-cd` (10.18.2, Argo CD v3.6) |
| Argo CD-projektek: `platform`, `product` (`AppProject`) | `argocd-projects` | `bedag/raw` (2.0.2) |
| Egy Argo CD Application komponensenként | `argocd-app-<alkalmazás>` | `bedag/raw` (2.0.2) |

**Az Argo CD Application-ök** (a neve megegyezik a 4. heti Helm-release nevével, lásd 4.3):

| Komponens | Application | Projekt | Cél-namespace | Forrás (verzió) |
|---|---|---|---|---|
| Ingress controller | `traefik` | `platform` | `ingress-controller` | `traefik` (41.2.0) |
| DNS-automatizmus | `external-dns` | `platform` | `external-dns` | `external-dns` (1.20.0) |
| Tanúsítványkezelés | `cert-manager` | `platform` | `cert-manager` | `cert-manager` (v1.19.4) |
| Let's Encrypt ClusterIssuer | `cluster-issuer` | `platform` | `cert-manager` | `bedag/raw` (2.0.2) |
| Demóalkalmazás | `colors` | `product` | `colors` | `oci://docker.io/ecklm/colors-demo-app` (1.0.0) |

**Az Argo CD-projektek:**

| Projekt | Mire való | Források | Cél-namespace-ek | Cluster-szintű erőforrás |
|---|---|---|---|---|
| `platform` | a közös infrastruktúra | a négy platform-chart repója | `ingress-controller`, `external-dns`, `cert-manager`, `kube-system` | bármi (CRD, ClusterRole, webhook, IngressClass, ClusterIssuer) |
| `product` | a fejlesztők alkalmazásai | `oci://docker.io/ecklm/*`, `https://github.com/vighsandor/*` | bármelyik, **kivéve** a platform namespace-eit és az `argocd`-t | csak `Namespace` |

**Hálózati tervezés:** minden környezet saját, át nem fedő `/12` VNet-tartományt kap, hogy egy későbbi peering ne igényeljen újraépítést. A Kubernetes service-tartomány (`10.0.0.0/16`, DNS IP: `10.0.0.10`) clusteren belüli, ezért minden környezetben ugyanaz.

---

## 3. Fejlesztői folyamat: hogyan igényelj környezetet?

Ez a fejezet a fejlesztőknek szól. A 4.0-s verziótól **a környezetigénylés egy pull request** a platform repójába. Ennek három előnye van: az igénylés és a megvalósítás ugyanaz a dokumentum; a pipeline már az igényléskor megmutatja, mi fog létrejönni; és minden igénylés, módosítás és jóváhagyás visszakereshető a git-történetben.

### 3.1 A folyamat áttekintése

```
Fejlesztő (te)                                   Platform engineer (én)
──────────────                                   ──────────────────────
1. Ágat nyitsz, felveszed a környezet
   tfvars fájlját, pull requestet nyitsz  ──►
                                                 2. A pipeline automatikusan lefut:
                                                    fmt + validate + plan minden környezetre
                                                 3. Átnézem a PR-t és a plan-t,
                                                    szükség esetén kiegészítem (hálózat)
                                                 4. Merge -> a pipeline apply-ja felépíti
5. Megkapod az átadó üzenetet             ◄──
6. Belépsz az Argo CD-be (Entra ID) és a clusterbe,
   telepíted az alkalmazásod (Argo CD product projekt)
   (a DNS-név és a TLS-tanúsítvány automatikusan elkészül)
7. Módosítás, meghosszabbítás, megszüntetés: újabb pull request
```

### 3.2 1. lépés: készülj fel

1. Legyen **Entra ID-fiókod** a céges tenantban, és tudd a **UPN**-edet (userPrincipalName). Ezzel lépsz be a clusterbe, és ezzel veszlek fel a környezet csoportjaiba. A UPN-t így kérdezheted le: `az ad signed-in-user show --query userPrincipalName -o tsv`.
2. Legyen **GitHub-fiókod**, és olvasási jogod a `vighsandor/cubixplatformeng` repóhoz. Ha nincs, kérd tőlem.
3. Telepítsd a szükséges eszközöket: `git`, `az` (Azure CLI), `kubectl`, `kubelogin`; opcionálisan `helm` és az `argocd` CLI.
4. Döntsd el előre:
   - a **projekt azonosítóját** (rövid, kisbetűs, kötőjeles, például `project-x`);
   - a **környezet nevét**: `sbx` kísérletezésre, `dev` közös fejlesztésre, `test` tesztelésre;
   - **kiknek** kell hozzáférés, és milyen szinten (írás vagy olvasás);
   - **meddig** lesz szükséged a környezetre.

### 3.3 2. lépés: nyiss pull requestet

1. Klónozd a repót, és nyiss egy ágat az igénylésnek:

   ```bash
   git clone https://github.com/vighsandor/cubixplatformeng.git && cd cubixplatformeng
   git switch platformeng-w3 && git pull
   git switch -c igenyles/<projekt>-<env>
   ```

2. Másold le a sablont a környezet nevére, és töltsd ki ([B. függelék](#b-függelék--a-környezet-tfvars-sablonja)):

   ```bash
   cp terraform/environments/_sablon.tfvars.example terraform/environments/<env>.tfvars
   ```

   - `project_name`, `env_name` (egyezzen a fájl nevével), `expires`;
   - a **`request`** blokk: az igénylő UPN-je, a csapat, az indoklás (mire kell) és a jóváhagyó (költséghely). **Külön űrlap nincs:** minden adat itt van, egy helyen; a Terraform ellenőrzi (pl. üres indoklással a plan hibát ad), és a state-ben is megőrzi;
   - `developers` (írás) és `readers` (olvasás): `név = "UPN"` soronként;
   - a hálózati tartományt (`vnet_address_space`, `node_subnet_prefix`) hagyd a sablon szerint, azt én töltöm ki.

3. Commitold és pushold, majd nyiss pull requestet a **`platformeng-w3`** ágra:

   ```bash
   git add terraform/environments/<env>.tfvars
   git commit -m "Környezetigénylés: <projekt> <env>"
   git push -u origin igenyles/<projekt>-<env>
   ```

   A GitHubon a **Compare & pull request** gombbal nyithatod meg. A pull request leírásába elég egy-két mondat (mit kérsz); az adatokat nem kell megismételni, azok a `tfvars`-ban vannak ([A. függelék](#a-függelék--a-pull-request-sablon)).

   > Ha nincs írási jogod a repóhoz, forkold, és onnan nyiss pull requestet; vagy küldd el nekem a kitöltött `tfvars` fájlt, és én nyitom meg a pull requestet helyetted.

### 3.4 3. lépés: kövesd a pull requestet

1. A pull requesten azonnal elindul a **Terraform** pipeline. Környezetenként lefut egy `Terraform Plan (<env>)` job, a pull request alján pedig a `Terraform Plan` ellenőrzés mutatja az összesített eredményt.
2. A job összefoglalójában (*Actions* → a futás → *Summary*) látod, mit hozna létre a plan a környezetedhez (benne az igénylésed adataival: `terraform_data.request`). Új környezetnél ez körülbelül 40 létrehozandó erőforrás, a többi környezetnél pedig `No changes`.
3. **2 munkanapon belül** átnézem: ha kell, kiegészítem (hálózati tartomány), kérdezek, vagy jóváhagyom.
4. A merge után először a sandbox frissül (`Terraform Apply (sbx)`), majd ha ott minden rendben, jóváhagyom a továbbvitelt, és a `Terraform Apply (<env>)` job felépíti a környezetedet (kb. 10–15 perc). A végén **átadó üzenetet** küldök a csatlakozás adataival; ugyanezek a futás összefoglalójában (`terraform output`) is ott vannak.

### 3.5 4. lépés: lépj be az Argo CD-be és a clusterbe

**Argo CD:** nyisd meg a `https://argocd.<projekt>.<env>.vighsandor.az.cubix-pe.hu` címet, és kattints a **LOG IN VIA ENTRA ID** gombra. A céges Entra ID-fiókoddal lépsz be, jelszót nem kell sehonnan kimásolni.

> - A tanúsítvány a Let's Encrypt staging végpontjáról jön, ezért a böngésző figyelmeztet (*Speciális → Tovább*).
> - Az első belépéskor az Entra ID engedélyt kér (*Permissions requested*: bejelentkezés és az alapprofil olvasása). Ezt egyszer kell elfogadni.
> - Ha belépés után üres a felület, nem vagy tagja a környezet egyik csoportjának sem (2.3): kérd a felvételed (pull request a `tfvars`-ra).

Parancssorból: `argocd login argocd.<projekt>.<env>.vighsandor.az.cubix-pe.hu --sso --grpc-web --insecure` (az `--insecure` a staging tanúsítvány miatt kell).

**Kubernetes:**

```bash
az login
az account set --subscription <ELŐFIZETÉS-AZONOSÍTÓ>
az aks get-credentials --resource-group <projekt>-<env>-aks --name <projekt>-<env> --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

**Sikeres, ha** a `kubectl get nodes` kiír egy node-ot `Ready` állapotban.

> Ha 403 / Forbidden hibát kapsz, jelentkezz ki és be újra (`az logout`, majd `az login`). A csoporttagság átvezetése néhány percig is tarthat.

### 3.6 5. lépés: telepítsd az alkalmazásod

Az alkalmazásod Argo CD Application-ként telepítsd a **product** projektbe. Így az Argo CD folyamatosan figyeli: ha valaki kézzel elállít valamit, visszaállítja, és a felületen látod az alkalmazás összes erőforrását, logját és eseményét.

**A) Az Argo CD felületén:** *+ NEW APP* →
- *Application Name*: `<app>`, *Project Name*: **`product`**, *Sync Policy*: *Automatic* (*Prune Resources*, *Self Heal* bekapcsolva), *Sync Options*: *Auto-Create Namespace*;
- *Source*: a chart (pl. `oci://…` vagy egy Helm-repó) és a verziója;
- *Destination*: *Cluster URL* `https://kubernetes.default.svc`, *Namespace* `<app>`;
- *Helm* → *Values*: a host és az annotáció (lent).

**B) Manifesttel** (`kubectl apply -f app.yaml`, ugyanez kódban tárolható):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]   # törléskor az erőforrások is törlődnek
spec:
  project: product
  destination:
    server: https://kubernetes.default.svc
    namespace: <app>
  source:
    repoURL: <chart-repó>            # pl. oci://docker.io/ecklm/colors-demo-app
    targetRevision: <verzió>         # pl. 1.0.0
    path: .                          # OCI-forrásnál; Helm-repónál helyette: chart: <név>
    helm:
      valuesObject:
        ingress:
          host: <app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt
  syncPolicy:
    automated: { enabled: true, prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

> A product projekt nem engedi a platform namespace-eit (`argocd`, `kube-system`, `ingress-controller`, `external-dns`, `cert-manager`) célként, és cluster-szintű erőforrásból csak namespace-t hozhat létre. Ha más forrásrepóra van szükséged, kérd pull requestben.

Az alkalmazás Ingress-erőforrásán két dolgot kell beállítanod:

1. A **host** a környezeted alzónáján belül legyen: `<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu`.
2. Az Ingress kapja meg a **`cert-manager.io/cluster-issuer: letsencrypt`** annotációt.

Ezután automatikusan: az **External DNS** 1–2 percen belül létrehozza az A rekordot, a **cert-manager** tanúsítványt kér, és néhány perc múlva az alkalmazás elérhető a `https://<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu` címen.

> - **Zónán kívüli hosztnév nem működik:** az External DNS figyelmen kívül hagyja.
> - **Az Ingress törlésekor a DNS-rekord is törlődik.**
> - Az `ingress-controller`, `external-dns` és `cert-manager` namespace a platform része, az Argo CD **platform** projektje kezeli: ha módosítod, az Argo CD perceken belül visszaállítja.
> - Egy Argo CD alkalmazást az Argo CD felületén (*DELETE*) vagy az Application törlésével szüntess meg, ne az erőforrásait töröld kézzel: azokat a selfHeal visszaállítaná.

### 3.7 Módosítás, meghosszabbítás, megszüntetés

Mindegyik ugyanúgy megy, mint az igénylés: egy pull request a környezeted `tfvars` fájljára.

| Igény | Mit módosítasz a `terraform/environments/<env>.tfvars`-ban |
|---|---|
| Új csapattag / kilépő tag | sor hozzáadása / törlése a `developers` vagy `readers` térképben |
| Meghosszabbítás | `expires` |
| Más méret | `node_vm_size`, `node_count` (indoklással a PR-ban) |
| Megszüntetés | jelezd a PR-ban „Megszüntetés” típussal; a lebontást én végzem (4.8) |

Új hosztnévhez és saját alkalmazáshoz nem kell pull request: elég egy Argo CD Application a product projektben (3.6).

---

## 4. Üzemeltetői folyamat: pipeline, Terraform és Argo CD

Ez a fejezet az én futtatókönyvem. Minden lépésnél leírom, mit csinálok, milyen eredményt várok, és miért így döntöttem.

### 4.0 Miért pipeline, és mire figyelek vele?

**Amit nyerek vele (CI/CD):**

- **Automatizáció:** a `plan` és az `apply` nem az én gépemen, nem az én emlékezetemből fut, hanem minden alkalommal ugyanazokkal a lépésekkel.
- **Egységes futtatókörnyezet:** a pipeline mindig tiszta, azonos környezetben fut (eszközverziók, bejelentkezés). A „nálam működik” hibák eltűnnek.
- **Auditálhatóság:** minden infrastruktúra-változáshoz tartozik egy pull request (ki kérte, miért), egy plan (mi fog történni), egy review (ki hagyta jóvá) és egy futási napló (mi történt).
- **Szabályok kikényszerítése:** a ruleset miatt a fő ágra csak olyan változás kerülhet, amelynek a plan-je lefutott; így hibás kódot nem lehet „véletlenül” élesíteni.

**Amire figyelnem kell (a pipeline imperatív eszköz):**

- **A Terraform csak akkor fut, amikor kérjük.** A pipeline nem figyeli folyamatosan a valóságot, ezért nincs automatikus drift-felderítés: egy kézi portálos módosítás csak a következő plan-nél derül ki. Ezért a portálon nem módosítok, és ha driftre gyanakszom, kézzel indítok egy plan-t (*Actions* → *Terraform* → *Run workflow*).
- **Minden műveletre (plan, apply, destroy) nekem kell felkészítenem a pipeline-t**, és a hibakezelés (újrapróbálás, zárolás) is az én dolgom. Ezért külön workflow-ja van a lebontásnak, és a plan/apply vár a state-zárolásra (`-lock-timeout`).
- A „folyamatosan figyelő” Terraform-funkciók (drift detection, automatikus újrapróbálás) fizetős termékben (Terraform Cloud) vannak. **A Kubernetesen belül ezt az 5.0-tól az Argo CD adja** (4.3.1).

**Miért Argo CD a Kubernetesen belül?** A Terraform pipeline push-alapú és alkalmi: csak akkor fut, amikor elindítjuk, és csak a saját Helm-release-ét látja, a release mögötti valódi Kubernetes-erőforrásokat nem. Az Argo CD a clusteren belül fut, és **folyamatosan** összeveti a kívánt állapotot a valóssal:

- **valódi Continuous Deployment:** a változás nem egy pipeline-futáshoz kötött, az Argo CD magától szinkronizál (pull-alapú telepítés);
- **a drift láthatóvá válik:** a felületen erőforrásonként látszik, mi tér el (*OutOfSync*), és mi nem egészséges (*Degraded*);
- **a kívánt állapot kikényszeríthető:** a selfHeal a kézi módosítást visszaállítja;
- **natív Kubernetes-eszközök:** Helm-chartok, sima manifestek, Kustomize; a logok, események és a readiness a felületen elérhetők.

### 4.1 Architektúra

```
 fejlesztő / én                  GitHub (vighsandor/cubixplatformeng)               Azure
 ───────────────                 ───────────────────────────────────               ─────
 ág + pull request  ──►  ruleset a platformeng-w3 ágon
                         (PR kötelező, "Terraform Plan" zöld,
                          az ág naprakész)
                         │
                         ├─ pull_request ─► Terraform Plan (env) ×N ──OIDC──►  github-repos
                         │                  fmt, init, workspace,           managed identity
                         │                  validate, plan -> artifact      (course-baseline)
                         │                                                   │
                         └─ merge (push) ─► Terraform Plan (env) ×N          ├─ Owner az előfizetésen
                                            1. Terraform Apply (sbx) ──────► ├─ Blob Data Contributor a state-en
                                            2. jóváhagyás (environment:      ├─ Groups Administrator (Entra)
                                               promotion), utána
                                               Terraform Apply (többi) ────►│
                                            (pontosan a plan-t alkalmazza)   │
                                                                             ├─ Directory Readers (Entra)
                                                                             ├─ Application Developer (Entra)
                                                                             └─ AKS RBAC Cluster Admin (közvetlenül)
                                                                                │
 AKS (környezetenként)                                                          ▼
 ┌───────────────────────────────────────────────────────────────────────────────────────┐
 │ namespace argocd:  Argo CD (helm_release)   AppProject: platform, product              │
 │                    Application-ök (helm_release + bedag/raw):                           │
 │                      platform: traefik, external-dns, cert-manager, cluster-issuer      │
 │                      product:  colors                                                   │
 │        │ AutoSync + selfHeal, folyamatos összevetés                                     │
 │        ▼                                                                                │
 │ ingress-controller, external-dns, cert-manager, colors ... (a tényleges erőforrások)   │
 └───────────────────────────────────────────────────────────────────────────────────────┘
   böngésző ──► https://argocd.<projekt>.<env>… ──► LOG IN VIA ENTRA ID ──► Entra ID-alkalmazás
                                                     (argocd-server: workload identity, titok nélkül)
```

**A repó felépítése:**

```
.
├── .github/
│   ├── workflows/terraform.yml          # plan pull requestre, apply a fő ágra
│   ├── workflows/terraform-destroy.yml  # egy környezet lebontása kézi indítással
│   ├── actions/terraform-setup, terraform-apply  # közös lépések (bejelentkezés, apply)
│   └── pull_request_template.md         # rövid leírás + review-lista (A. függelék)
├── terraform/                           # EGY kód minden környezetre
│   ├── provider.tf      # backend (state), providerek: azurerm, azuread, helm, time
│   ├── common.tf        # közös változók, nevek, tagek, workspace-védelem
│   ├── network.tf       # VNet, alhálózat
│   ├── aks.tf           # AKS, a cluster identitása, a csoportok jogai, RBAC-várakozás
│   ├── entra.tf         # Entra ID-csoportok és tagjaik (név -> UPN -> object ID)
│   ├── dns.tf           # alzóna, NS-delegáció
│   ├── argocd.tf        # Argo CD, Entra ID-belépés, projektek, Application-ök
│   ├── external-dns.tf  # External DNS: identitás, federáció, jog és az Application leírása
│   ├── ingress.tf       # Traefik (Application)
│   ├── cert-manager.tf  # cert-manager és a Let's Encrypt ClusterIssuer (Application-ök)
│   ├── demo-app.tf      # colors demóalkalmazás (Application, product projekt)
│   ├── migracio.tf      # átállás a 4. heti helm_release-ekről (removed blokkok)
│   ├── outputs.tf
│   └── environments/
│       ├── sbx.tfvars, dev.tfvars, ...  # környezetenként egy fájl = egy igénylés
│       └── _sablon.tfvars.example       # sablon az új igénylésekhez
├── bootstrap/           # egyszeri beállítás (pipeline-identitás, secretek, ruleset)
├── scripts/
│   ├── tf.sh                   # helyi futtatás hibakereséshez
│   ├── jovahagyas.sh           # a sandbox utáni környezetek továbbvitelének jóváhagyása
│   ├── lebontas.sh             # környezetek lebontása a destroy pipeline-nal
│   └── segedscript-futtatas.sh # a segédscript futtatása, kimenet Markdownba
├── kimenetek/           # a segédscript kimenete (erőforráslista)
└── dokumentacio/        # ez a leírás
```

### 4.2 Egyszeri beállítás: a pipeline Azure-identitása és a GitHub repo

Ezt egyszer, a platform indulásakor csinálom meg, a saját fiókommal. Mindkét script újrafuttatható: ami már megvan, azt nem hozza létre újra.

> **Miért script, és nem Terraform?** Ezek az erőforrások (a pipeline identitása, a jogai, a GitHub-beállítások) a környezetek *előfeltételei*, ezért nem lehetnek ugyanabban a Terraform-kódban, amelyet maga a pipeline futtat: egy hibás változtatással a pipeline a saját jogát vonhatná meg. Éles környezetben ezt is Terraform írná le, egy külön, a projekten kívüli „platform-bootstrap” kódban, saját state-tel (az `azurerm`, `azuread` és `github` providerrel). A két újrafuttatható script ennek egy egyszerűbb középútja: ugyanúgy kódban van, és bármikor újrafuttatható.

**1. A pipeline identitása** – `bootstrap/01-azure-github-identity.sh`

```bash
az login
./bootstrap/01-azure-github-identity.sh
```

| Mit hoz létre | Miért |
|---|---|
| `github-repos` managed identity a `course-baseline`-ban | a pipeline ezzel az identitással dolgozik az Azure-ban; nincs jelszava |
| 6 federated credential: a `platformeng-w3` ágra, a pull requestekre és a `promotion` GitHub environmentre (ha egy job environmentben fut, a token subjectje `…:environment:promotion`), mindegyik az új (módosíthatatlan azonosítós: `repo:vighsandor@<id>/cubixplatformeng@<id>:…`) és a régi (`repo:vighsandor/cubixplatformeng:…`) subject-formátumban | a GitHub OIDC-tokenjét az Entra ID csak akkor fogadja el, ha a `sub` mező pontosan egyezik; a GitHub a repó beállításától függően az egyik vagy a másik formát küldi, így mindkettőt felveszem |
| **Owner** az előfizetésen | erőforrásokat hoz létre, és szerepköröket oszt ki (pl. a csoportoknak az AKS-en) |
| **Storage Blob Data Contributor** a `platencbvighsandor` storage accounton | a state olvasása, írása, zárolása (az Owner adat-jogot nem ad) |
| **Groups Administrator** Entra ID-szerepkör | Entra ID-csoportok létrehozása és a tagság kezelése |
| **Directory Readers** Entra ID-szerepkör | a felhasználók kikeresése UPN alapján (`data "azuread_user"`) és a saját service principalja kikeresése |
| **Application Developer** Entra ID-szerepkör (5. hét) | az Argo CD Entra ID-alkalmazásának (app registration + service principal) létrehozása. A létrehozó automatikusan tulajdonos lesz, így a federated credentialt is ő kezeli; más alkalmazáshoz nem nyúlhat |

> Az Azure-szerepkörök (Owner, Blob Data Contributor) és az Entra ID-szerepkörök (Groups Administrator, Directory Readers, Application Developer) két külön világ: az előbbiek az Azure-erőforrásokra, az utóbbiak a címtárra (felhasználók, csoportok) adnak jogot. Az Entra ID-szerepkörök kiosztásához Global Administrator vagy Privileged Role Administrator jog kell.

**2. A GitHub repo** – `bootstrap/02-github-repo.sh` (a `gh` CLI-vel, a repo adminjaként)

```bash
gh auth login
./bootstrap/02-github-repo.sh secrets          # AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
./bootstrap/02-github-repo.sh default-branch   # a platformeng-w3 legyen az alapértelmezett ág
./bootstrap/02-github-repo.sh environments     # "promotion" environment: kötelező jóváhagyó (én), csak a fő ágról
# ... az első sikeres pipeline-futás után:
./bootstrap/02-github-repo.sh ruleset
```

- **Secretek:** a három érték azonosító, nem jelszó. Secretként azért tárolom őket, hogy ne kelljen a workflow-ba égetni, és máshol is ugyanígy használható legyen.
- **`promotion` environment:** a sandbox utáni környezetek apply-ja ebben fut. A GitHub ilyenkor megállítja a jobot, amíg egy kijelölt jóváhagyó (én) jóvá nem hagyja (*Review deployments*), és csak a `platformeng-w3` ágról enged telepíteni. (Privát repónál a kötelező jóváhagyó a GitHub fizetős csomagjaiban érhető el; ingyenes csomagban a sorrend ettől még megmarad.)
- **Alapértelmezett ág:** a kézzel indítható workflow-k (pl. a lebontás) csak az alapértelmezett ágon lévő workflow-fájlból indíthatók, és a pull requestek is ezt kínálják fel célágnak.
- **Ruleset** a `platformeng-w3` ágon (*Settings* → *Rules* → *Rulesets*):

  | Szabály | Beállítás | Miért |
  |---|---|---|
  | Require a pull request before merging | be, 0 kötelező jóváhagyás | közvetlen push tiltva; egyedül dolgozom, ezért jóváhagyást nem várok el, de a PR (plan + napló) kötelező |
  | Require status checks to pass | `Terraform Plan` | csak akkor lehet merge-ölni, ha az `fmt`, a `validate` és a `plan` minden környezetre lefutott |
  | Require branches to be up to date before merging | be | **semi-linear history:** csak a fő ág tetejére épülő ágat lehet merge-ölni, így a plan pontosan arra az állapotra futott, ami a merge után lesz |
  | Block force pushes, Restrict deletions | be | a fő ág története nem írható át és nem törölhető |

  > A kötelező ellenőrzés fix nevű kell legyen, a plan jobok neve viszont környezetenként más (`Terraform Plan (sbx)`, `Terraform Plan (dev)`). Ezért van egy összesítő job, amelynek a neve pontosan `Terraform Plan`, és csak akkor zöld, ha minden környezet plan-je sikeres. Így egy új környezet felvétele után sem kell a rulesetet módosítani.

### 4.3 A kód felépítése

**Egy kód, több környezet: workspace + tfvars.** A 3.0-ban környezetenként külön könyvtár (és duplikált kód) volt. Most egyetlen kód van, a környezetet a **Terraform workspace** választja ki: a backend workspace-enként külön state-blobot használ (`project-x.tfstateenv:sbx`), a bemeneteket pedig a `environments/<env>.tfvars` adja.

```bash
terraform workspace select -or-create dev
terraform plan -var-file=environments/dev.tfvars
```

**Workspace-védelem.** A workspace önmagában veszélyes: a dev változókkal a sandbox workspace-ében futtatva a sandboxot írnám át. Ezt egy előfeltétel (precondition) zárja ki:

```hcl
resource "terraform_data" "workspace_guard" {
  input = var.env_name
  lifecycle {
    precondition {
      condition     = terraform.workspace == var.env_name
      error_message = "A workspace (...) nem egyezik a környezettel (...)."
    }
  }
}
```

**A Kubernetesen belüli rész is Terraformból indul.** A Helm providerrel a Terraform ugyanabban a futásban, ugyanabból a kódból telepíti az Argo CD-t, és hozza létre az Argo CD Application-öket (4.3.1). Ennek fő előnye, hogy **a Terraform-erőforrások közvetlenül elérhetők**: az External DNS Application values-ába a managed identity Client ID-ja, az Argo CD beállításaiba az Entra ID-alkalmazás és a csoportok azonosítója, a zóna neve és a resource groupok neve közvetlenül az erőforrásokból kerül, nincs kézi másolás vagy sablonkitöltés. (A másik út, a Helm-parancsok a pipeline-ban, azt jelentené, hogy minden Helm-műveletet és -kapcsolót a pipeline-ban újra kellene implementálni.)

- **Bejelentkezés a clusterbe:** az AKS-en nincsenek helyi fiókok, ezért a Helm provider a `kubelogin`-nal kér tokent az Azure CLI bejelentkezéséből (`--login azurecli`). Helyben ez a saját fiókom, a pipeline-ban a `github-repos` identitás; ezért a pipeline identitásának (`platform_admin_service_principals`) cluster-admin jog kell. A pipeline identitása tagja a platform-admins csoportnak, és **közvetlenül is megkapja** az *Azure Kubernetes Service RBAC Cluster Admin* szerepkört (`azurerm_role_assignment.aks_pipeline`). Erre azért van szükség, mert a pipeline az AKS-tokent a futás elején kéri, amikor egy új környezet csoportjának még nem tagja. A token `groups` claimjéből így hiányzik a csoport, és a csoporton keresztüli jog csak a következő futásban működne. A közvetlen szerepkör-hozzárendelést az Azure szerveroldalon értékeli ki. Ez a „jogot csak csoport kap” szabály egyetlen, tudatos kivétele, és egy gépi identitásra vonatkozik, nem személyre.
- **Nyers Kubernetes-erőforrások** (Argo CD Application, AppProject, ClusterIssuer): a Helm provider nem tud nyers manifestet telepíteni, a Kubernetes provider pedig a CRD-k miatt nehézkes (a plan-hez már léteznie kellene a CRD-nek), ezért a `bedag/raw` „csomagoló” chartot használom: a chart a values-ban kapott erőforrásokat telepíti.
- **Várakozás az RBAC-ra:** új környezetnél a csoporttagság és az AKS-szerepkör néhány perc alatt lép életbe. A Helm-telepítések egy `time_sleep` (180 s) után indulnak, különben az első futás 403-at kapna.
- **Sorrend:** a Terraform a függőségek alapján rendezi: AKS → szerepkörök → várakozás → Argo CD → projektek → Application-ök. Az Application-ök egymás közti sorrendjét már az Argo CD kezeli (4.3.1).

#### 4.3.1 Argo CD (`argocd.tf`)

**Telepítés.** Az Argo CD-t a Terraform `helm_release`-zel telepíti (`argo-cd` chart). A felülete a `https://argocd.<projekt>.<env>.vighsandor.az.cubix-pe.hu` címen érhető el: Ingress (Traefik), DNS-rekord (External DNS) és tanúsítvány (cert-manager) ugyanúgy, mint bármely alkalmazásnál. A TLS-t a Traefik zárja le, ezért az `argocd-server` HTTP-n fut mögötte (`server.insecure`). A Dex nincs telepítve, mert az Argo CD közvetlenül az Entra ID-hoz fordul.

**Application-ök Terraformból.** Egy Argo CD Application is csak egy Kubernetes-erőforrás (CRD), ugyanaz, amit a felületen összekattintva az Argo CD maga is létrehoz. A Terraform ezeket a `bedag/raw` charttal hozza létre az `argocd` namespace-ben (az Argo CD alapértelmezetten csak innen olvassa az Application-öket). Komponensenként egy `helm_release.argocd_app["<név>"]`: így a plan-ben komponensenként látszik a változás. A komponensek leírása a saját fájljukban van (`local.app_traefik`, `local.app_external_dns` …), azonos szerkezetben; az `argocd.tf` alakítja őket egységes Application-ökké. A Helm-értékeket `valuesObject`-ként adom át (a legmagasabb precedenciájú forma a `parameters` után), így azok struktúrát kapnak, nem egy nagy szöveget.

**Minden Application-ön:**

| Beállítás | Érték | Miért |
|---|---|---|
| Projekt | `platform` vagy `product` | csoportosítás és jogosultság: a platformkomponenseket a fejlesztők nem módosíthatják, a product alkalmazások pedig nem nyúlhatnak a platform namespace-eihez |
| AutoSync | `automated: { enabled, prune, selfHeal }` | beavatkozás nélküli szinkron; a kódból eltűnt erőforrást törli (prune), a kézi módosítást visszaállítja (selfHeal) |
| Újrapróbálás | `retry: limit 10, 15 s-tól 5 percig` | az alkalmazások egymásra épülnek (a ClusterIssuer a cert-manager CRD-jére, az Ingress-ek a Traefikre): ami még nem tud szinkronizálni, az magától újrapróbálja |
| Finalizer | `resources-finalizer.argocd.argoproj.io` | az Application törlésekor az Argo CD a létrehozott erőforrásokat is törli; nélküle az erőforrások gazdátlanul a clusterben maradnának |
| `CreateNamespace=true` | – | a cél-namespace-t az Argo CD hozza létre |
| `ServerSideApply=true` | Traefik, cert-manager | a nagy CRD-k kliensoldali apply-jal túllépnék az annotáció méretkorlátját |
| `ignoreDifferences` | cert-manager webhook `namespaceSelector` | a Kubernetesben „magasabb erők” (mutating webhookok) utólag kiegészítik az objektumot; enélkül az alkalmazás folyamatosan *OutOfSync* lenne |
| `SkipDryRunOnMissingResource=true` | ClusterIssuer | a CRD még nem létezik, amikor az Argo CD először próbálkozik |

**Terraform-szintű függőség.** Minden Application `helm_release`-e függ az Argo CD-től és a projektektől (`depends_on`): amíg az Argo CD CRD-i és a projektek nem léteznek, az Application létrehozása úgysem sikerülne. A függőség a lebontásnál is számít: a finalizer kétélű fegyver, mert ha az Argo CD előbb tűnik el, mint az Application-ök, a finalizereket senki nem dolgozza fel, és az erőforrások gazdátlanul maradnak. Ezért a lebontás sorrendje: Application-ök → 2 perc várakozás (`time_sleep.argocd_app_cleanup`, ezalatt az Argo CD letörli az alkalmazások erőforrásait) → projektek → Argo CD.

**Entra ID-belépés titok nélkül.** A Terraform környezetenként létrehoz egy Entra ID-alkalmazást (`<projekt>-<env>-argocd`):
- visszahívási cím: `https://argocd.<…>/auth/callback` (és a CLI-hez `http://localhost:8085/auth/callback`);
- `groupMembershipClaims = SecurityGroup`: a tokenbe bekerülnek a felhasználó biztonsági csoportjai;
- **titkos kulcs (client secret) nincs**: az `argocd-server` service account workload identityvel igazolja magát az Entra ID felé (`azure.useWorkloadIdentity: true`). Az alkalmazás federated credentialje a cluster OIDC-kibocsátóját és a `system:serviceaccount:argocd:argocd-server` subjectet fogadja el. Nincs lejáró titok, nincs mit forgatni, és a környezet lebontása-újraépítése után sem kell semmit kézzel kimásolni.
- Az Argo CD RBAC-ja (`policy.csv`) a három környezeti csoport object ID-jához rendel szerepkört (2.3). A helyi `admin` fiók ki van kapcsolva (`argocd_admin_enabled = false`); vészhelyzetben egy `tfvars`-sorral visszakapcsolható, a jelszava ilyenkor az `argocd-initial-admin-secret` secretben van.

**Átállás a 4. heti Helm-telepítésekről (`migracio.tf`).** Egy már futó környezetben a Terraform a régi `helm_release`-eket nem uninstallálja, hanem `removed { lifecycle { destroy = false } }` blokkokkal kiveszi a state-ből. Az Argo CD Application-ök ugyanazzal a névvel (= release-névvel) ugyanazokat az erőforrásokat írják le, így átveszik őket leállás nélkül. Új környezetben ezek a blokkok nem csinálnak semmit. (A `removed` blokk miatt kell a Terraform ≥ 1.7.)

**Rögzített verziók:** Terraform ≥ 1.7, `azurerm` 5.3.0, `azuread` 3.9.0, `helm` 3.2.0, `time` 0.14.2, és minden chart pontos verzióval (Argo CD: `argo-cd` 10.18.2).

**A portálbeállítások Terraform-megfelelői** (a ClickOps-os kiindulópontból):

| ClickOps (portál) | Terraform |
|---|---|
| Pricing tier: Free; Automatic upgrade: Disabled; Node security channel: None | `sku_tier = "Free"`, `automatic_upgrade_channel = null`, `node_os_upgrade_channel = "None"` |
| Node pool `system`, `Standard_D2as_v5`, Manual, 1 node | `node_provisioning_profile { mode = "Manual" }`, `default_node_pool { … }` |
| Azure CNI Overlay, saját VNet, user assigned identity | `network_profile { network_plugin_mode = "overlay" }`, `vnet_subnet_id`, `identity { type = "UserAssigned" }` |
| Entra ID + Azure RBAC, Local accounts: Disabled | `azure_active_directory_role_based_access_control { azure_rbac_enabled = true }`, `local_account_disabled = true` |
| OIDC + Workload Identity | `oidc_issuer_enabled = true`, `workload_identity_enabled = true` |
| „Child of an existing zone” | `azurerm_dns_ns_record.delegation` a szülőzónában |
| `helm upgrade --install …` (Traefik, External DNS, cert-manager, colors) | Argo CD Application (`helm_release.argocd_app`, `bedag/raw`) |
| `kubectl apply -f cluster-issuer.yaml` | Argo CD Application a `bedag/raw` charttal |
| Argo CD felület: *+ NEW APP* (General, Source, Destination, Helm values, Sync Policy) | az Application `spec`-je: `project`, `source`, `destination`, `helm.valuesObject`, `syncPolicy` |
| Entra ID: *App registrations → New registration*, *Token configuration → Add groups claim*, *Federated credentials* | `azuread_application`, `azuread_service_principal`, `azuread_application_federated_identity_credential` |

### 4.4 A pipeline működése (`.github/workflows/terraform.yml`)

| Esemény | Mi fut | Eredmény |
|---|---|---|
| **pull request** a `platformeng-w3` ágra | `Terraform Plan (<env>)` minden környezetre, majd az összesítő `Terraform Plan` | a PR-on látszik, mit változtatna a merge; a ruleset ennek zöld állapotát várja |
| **push** a `platformeng-w3` ágra (= merge) | újra plan; **1.** `Terraform Apply (sbx)` jóváhagyás nélkül; **2.** ha az sikeres: a többi környezet `Terraform Apply (<env>)` jobja megvárja a jóváhagyást (`promotion` environment), és csak utána fut | a változás először a sandboxon élesedik, a többi környezetben csak ellenőrzés és jóváhagyás után |
| kézi indítás (*Run workflow*) | plan (és a fő ágon apply) | drift-ellenőrzés, újrafuttatás |

**A plan job lépései:** checkout → Azure-bejelentkezés (OIDC) → Terraform és kubelogin telepítése → `terraform fmt -check` → `init` → `workspace select -or-create <env>` → `validate` → `plan -var-file=… -out=tfplan` → a plan összefoglalója a futás *Summary* oldalára → a plan feltöltése artifactként.

**Az apply job** letölti **ugyanannak a futásnak** a plan-jét, és pontosan azt alkalmazza (`terraform apply tfplan`), nem számol újat. Így az élesedik, amit a napló mutat. A merge után a plan újra lefut, mert a pull request plan-je a merge előtti állapotra készült.

**Lépcsőzetes élesítés (miért és hogyan).** A `validate` és a `plan` nem szűr ki mindent: egy hibás Helm-érték, egy kvótahiba vagy egy jogosultsági gond csak az apply-nál derül ki. Ezért merge után először csak a sandbox frissül (`apply-first` job). A többi környezet apply-ja (`apply-promote`) csak akkor indul, ha a sandboxé sikeres volt, és akkor is megáll a `promotion` environment jóváhagyásánál. Jóváhagyás előtt megnézem a sandboxot (Argo CD: *Synced* / *Healthy*, a demóalkalmazás válaszol), és csak utána engedem tovább:

```bash
./scripts/jovahagyas.sh          # a fő ág legutóbbi futása; vagy: Actions -> a futás -> Review deployments
```

> - A plan artifact 7 napig marad meg: eddig lehet jóváhagyni. Ha közben újabb merge történt, a régi plan elavult (*Saved plan is stale*): ilyenkor a régi futást nem hagyom jóvá, hanem az újat.
> - Ha egy változás csak egy nem-sandbox környezetet érint (pl. a `dev` meghosszabbítása), a sandbox apply-ja `No changes`, és utána jön a jóváhagyás.
> - A közös lépéseket (bejelentkezés, Terraform és kubelogin telepítése, apply) két composite action tartalmazza (`.github/actions/`), így a plan, a két apply és a destroy job nem ismétli őket.

**Környezetek felderítése:** az első job kilistázza a `terraform/environments/*.tfvars` fájlokat, és ebből lesz a mátrix (külön: a sandbox és „a többi”). **Új környezet = új tfvars fájl**, a workflow-t nem kell módosítani.

**Párhuzamosság és zárolás:** a környezetek egymástól függetlenül, párhuzamosan futnak; egy környezeten egyszerre csak egy apply futhat (`concurrency`), és a plan/apply legfeljebb 10 percig vár a state-zárolásra (`-lock-timeout=10m`).

### 4.5 Egy igénylés kiszolgálása (review → merge → apply)

1. **Beérkezik a pull request.** Ellenőrzöm a `tfvars` `request` blokkját: igénylő, csapat, indoklás, jóváhagyó, és a lejáratot. (A formai ellenőrzést, pl. hogy az indoklás nem üres, a Terraform már a plan-nél elvégzi.)
2. **Kiegészítem, ha kell.** Új környezetnél kiosztom a következő szabad hálózati tartományt, és egy commitot pusholok a PR ágára:

   | Környezet | `vnet_address_space` | `node_subnet_prefix` |
   |---|---|---|
   | `sbx` | `10.224.0.0/12` | `10.224.0.0/24` |
   | `dev` | `10.240.0.0/12` | `10.240.0.0/24` |
   | következő | `10.208.0.0/12` | `10.208.0.0/24` |

3. **Kvóta.** *Előfizetés → Usage + quotas*, Sweden Central: *Standard DASv5 Family vCPUs* és *Total Regional vCPUs*. Egy alapértelmezett környezet 2 vCPU. (Az `sbx` és a `dev` együtt pont kitölti a 4 vCPU-s DASv5-kvótát.)
4. **A plan átnézése** (*Checks* → *Terraform Plan (<env>)* → *Summary*):
   - új környezetnél csak `+ create` sorok, a többi környezetnél `No changes`;
   - módosításnál pontosan a kért változás, semmi más (pl. tag-módosítás `~ update in-place`);
   - **csere (`-/+ must be replaced`) esetén megállok**, és kiderítem, miért: az AKS sok beállítása csak újraépítéssel módosítható.
5. **Az ág naprakész?** Ha a fő ág közben továbblépett, a GitHub az *Update branch* gombot kínálja (a ruleset csak naprakész ágat enged merge-ölni). Frissítés után a plan újra lefut.
6. **Merge.** A pipeline először a sandboxot frissíti (`Terraform Apply (sbx)`). Ha az sikeres, és a sandboxban minden rendben, **jóváhagyom a továbbvitelt** (`./scripts/jovahagyas.sh` vagy *Review deployments*), és a `Terraform Apply (<env>)` job létrehozza / módosítja a környezetet.
7. **Ellenőrzés és átadás** (4.6).

### 4.6 Ellenőrzés és átadás

1. Az apply futás *Summary* oldalán a `terraform output`: cluster, DNS-zóna, csoportok, demó URL, Argo CD URL, csatlakozási parancsok.
2. Csatlakozom, és ellenőrzöm a láncot:

   ```bash
   az aks get-credentials -g <projekt>-<env>-aks -n <projekt>-<env> --overwrite-existing
   kubelogin convert-kubeconfig -l azurecli
   kubectl get nodes
   kubectl get pods,ingress -A
   kubectl get clusterissuer,certificate -A
   kubectl get applications,appprojects -n argocd      # minden alkalmazás: Synced, Healthy
   curl -k https://colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu   # <title>Rollouts Demo</title>
   ```

   Végül belépek az Argo CD felületére Entra ID-val (`https://argocd.<projekt>.<env>…`), és megnézem, hogy mind az öt alkalmazás *Synced* és *Healthy*.

3. Átadó üzenet:

   ```text
   Szia <név>!

   Elkészült a(z) <projekt> projekt <env> környezete (PR: #<szám>).

   - Előfizetés: <ELŐFIZETÉS-AZONOSÍTÓ>
   - AKS cluster: <projekt>-<env> (resource group: <projekt>-<env>-aks)
   - DNS-zóna: <projekt>.<env>.vighsandor.az.cubix-pe.hu
     (ezen belül bármilyen hosztnevet használhatsz, a DNS-rekord automatikusan létrejön)
   - Ingress class: traefik, ClusterIssuer: letsencrypt (staging)
   - Csoport, amelynek tagja lettél: <projekt>-<env>-developers (RBAC Writer)
   - Demó: https://colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu
   - Argo CD: https://argocd.<projekt>.<env>.vighsandor.az.cubix-pe.hu (LOG IN VIA ENTRA ID);
     a saját alkalmazásaidat a product projektbe telepítheted

   Csatlakozás:
     az aks get-credentials -g <projekt>-<env>-aks -n <projekt>-<env> --overwrite-existing
     kubelogin convert-kubeconfig -l azurecli

   Lejárat: <dátum>. Módosítás, meghosszabbítás: pull request a környezeted tfvars fájljára.
   ```

### 4.7 Módosítás és drift

- **Minden módosítás pull request** a `tfvars`-ra (tagok, lejárat, méret) vagy a kódra (platformváltozás). A kódváltozás minden környezet plan-jében megjelenik, így látom, hogy melyiket hogyan érinti.
- **Drift a Kubernetesen belül:** ezt az Argo CD folyamatosan figyeli és a selfHeal automatikusan visszaállítja; a felületen az alkalmazás *History and rollback* és *Events* nézete mutatja, mi történt. Ha egy eltérés jogos (pl. egy mutating webhook miatt), az Application `ignoreDifferences` beállításába kerül (pull request).
- **Drift az Azure-ban** (a Terraform-erőforrásoknál): kézzel indítok egy futást (*Actions* → *Terraform* → *Run workflow*, ág: `platformeng-w3`). A plan megmutatja az eltérést; a fő ágon az apply vissza is állítja a kódban leírt állapotot. Ha az eltérés jogos volt, előbb a kódot igazítom (pull request).

### 4.8 Megszüntetés (lebontás)

A lebontás szándékosan **nem automatikus**, és két lépésből áll:

1. **Lebontás a pipeline-nal:** *Actions* → **Terraform destroy** → *Run workflow* (ág: `platformeng-w3`), `environment`: a környezet neve, `confirm`: még egyszer a neve. A workflow a `terraform destroy`-jal mindent töröl, amit a kód létrehozott: először az Argo CD Application-öket (a finalizer miatt az Argo CD az általuk létrehozott erőforrásokat is törli), majd az Argo CD-t, az AKS-t, a hálózatot, az identitásokat, a DNS-zónát és a delegációt, valamint az Entra ID-csoportokat, a tagságokat és az Argo CD Entra ID-alkalmazását is. Scriptből: `./scripts/lebontas.sh <env>`.
2. **A környezet kivezetése a kódból:** pull request, amely törli a `terraform/environments/<env>.tfvars` fájlt. Ezt **a lebontás után** kell merge-ölni: ha előbb törlöm a fájlt, a pipeline már nem látja a környezetet, és a lebontást kézzel kellene elvégezni.

> Ha egy környezetre csak átmenetileg nincs szükség (pl. a hétvégére), elég az 1. lépés. Fontos azonban, hogy **a fő ágra kerülő következő merge újra felépíti**, mert a kódban továbbra is benne van; ez a deklaratív működés lényege.

### 4.9 Helyi futtatás (hibakereséshez)

A rendes út a pipeline. Hibakereséshez vagy ha a GitHub nem elérhető, helyben is futtatható, a saját fiókommal:

```bash
az login
./scripts/tf.sh dev plan        # csak megnéz, nem módosít
./scripts/tf.sh dev apply       # csak vészhelyzetben: megkerüli a review-t
```

---

## 5. Hibaelhárítás

| Tünet | Ok | Teendő |
|---|---|---|
| `azure/login`: *AADSTS700213 / AADSTS70021: No matching federated identity record found* | A GitHub OIDC-tokenjének `sub` mezője nem egyezik egyik federated credentiallel sem (más ág, repo-átnevezés, más subject-formátum) | A hibaüzenetben szerepel a kapott subject; vedd fel azt is federated credentialként (`01-azure-github-identity.sh`, vagy a portálon) |
| `azure/login` a `Terraform Apply` jobban: *AADSTS70021 … environment:promotion* | Hiányzik a `promotion` environment federated credentialje | `01-azure-github-identity.sh` újrafuttatása |
| A `Terraform Apply (<env>)` job „Waiting” állapotban áll | A `promotion` environment jóváhagyásra vár (ez a szándékos működés) | `./scripts/jovahagyas.sh`, vagy *Actions* → a futás → *Review deployments* |
| Jóváhagyás után: *Saved plan is stale* | A jóváhagyásig újabb apply futott ugyanarra a környezetre | A régi futást hagyd figyelmen kívül; a legújabb futást hagyd jóvá (vagy *Re-run all jobs*) |
| A plan: *Invalid value for variable … request* | A `request` blokk hiányos (pl. üres indoklás, UPN helyett név) | A hibaüzenet szerint javítsd a `tfvars`-t |
| `terraform init`: *403 AuthorizationPermissionMismatch* | Hiányzik a *Storage Blob Data Contributor* a state storage accountján | `01-azure-github-identity.sh` újrafuttatása, pár perc várakozás |
| `azuread_group`: *Authorization_RequestDenied* | A pipeline identitásának nincs *Groups Administrator* szerepköre | `01-azure-github-identity.sh`; az Entra-szerepkör életbe lépése akár 10–15 perc |
| `data.azuread_user`: *User not found* / *Insufficient privileges* | Rossz UPN a `tfvars`-ban, vagy hiányzik a *Directory Readers* | A UPN ellenőrzése (`az ad user show --id <UPN>`), a szerepkör ellenőrzése |
| `Error acquiring the state lock` | Egy másik futás (pl. egy merge apply-ja) épp ugyanazt a környezetet zárolja | A futás 10 percig vár; ha így is elbukik, *Re-run all jobs* |
| A workspace-védelem hibát ad | A workspace és az `env_name` nem egyezik (pl. elgépelt fájlnév) | A `tfvars` fájl neve, az `env_name` és a workspace legyen azonos |
| `helm_release`: *Unauthorized* / *forbidden* az első futáskor | Az AKS-szerepkör vagy a csoporttagság még nem lépett életbe | *Re-run all jobs* (az új plan már csak a hiányzó részt tartalmazza) |
| `helm_release`: *… is forbidden: User "<object ID>" cannot … User does not have access to the resource in Azure* új környezet első futásakor | A pipeline AKS-tokenje a futás elején készült, amikor az identitás még nem volt tagja az új platform-admins csoportnak | A pipeline identitása közvetlen szerepkört kap (`aks_pipeline`), ezért ez nem fordulhat elő. Régebbi kódnál: *Re-run all jobs*, az új futás tokenje már tartalmazza a csoportot. |
| `kubelogin: executable file not found` | Hiányzik a kubelogin (a pipeline-ban az `azure/use-kubelogin` lépés, helyben a telepítés) | Telepítés |
| `helm_release`: *Kubernetes cluster unreachable … exec: executable kubelogin failed with exit code 1* (az AKS létrehozása után), vagy *AADSTS700024: Client assertion is not within its valid time range* | A GitHub OIDC-tokenje csak néhány percig érvényes. Ha az Azure CLI csak az AKS létrehozása után (10+ perc) kér tokent az AKS scope-ra, a kérés már lejárt tokennel menne. | A workflow a bejelentkezés után rögtön kér egy AKS-tokent (*AKS-token előtöltése* lépés), amely kb. 60–90 percig érvényes. Ha mégis előfordul: *Re-run **all** jobs*, mert a csak az apply-t újrafuttató próbálkozás elavult plan-nel indulna (*Saved plan is stale*). |
| A PR-on a merge gomb szürke: *This branch is out-of-date* | A ruleset csak naprakész ágat enged merge-ölni | *Update branch* a PR-on, utána a plan újra fut |
| A PR-on a `Terraform Plan` ellenőrzés „Expected — Waiting for status” | A workflow nem futott le (pl. a célág nem a `platformeng-w3`) | A PR célága legyen `platformeng-w3`; szükség esetén zárd be és nyisd újra a PR-t |
| `terraform fmt -check` elbukik | Formázási eltérés | Helyben `terraform fmt -recursive terraform/`, commit, push |
| Kvótahiba az apply-ban | Elfogyott a DASv5- vagy a régiós vCPU-kvóta | Kvótaemelés, `node_vm_size` másik családra (arra is kell kvóta), vagy egy nem használt környezet lebontása |
| `azuread_application`: *Authorization_RequestDenied: Insufficient privileges* | A pipeline identitásának nincs *Application Developer* szerepköre | `01-azure-github-identity.sh` újrafuttatása; az Entra-szerepkör életbe lépése akár 10–15 perc |
| Argo CD belépés: *AADSTS50011: The redirect URI … does not match* | Az Entra ID-alkalmazás visszahívási címe nem egyezik az Argo CD címével | A `terraform plan` mutatja az eltérést; a címet a Terraform állítja (`argocd.tf`) |
| Argo CD belépés: *AADSTS700213 / AADSTS70021* az `argocd-server` logjában | A workload identity federated credential nem egyezik (más namespace / service account, vagy a cluster újraépült más OIDC-kibocsátóval) | `kubectl -n argocd logs deploy/argocd-server`; Terraform-futás (a credential a cluster kibocsátójából jön) |
| Argo CD belépés után üres felület, „no permissions” | A felhasználó nem tagja a környezet egyik csoportjának sem, vagy a tokenben nincs `groups` claim | Csoporttagság a `tfvars`-ban; a tokent a *User Info* oldalon lehet ellenőrizni (az Argo CD felületén bal oldalt) |
| Az Entra ID az első belépéskor „Need admin approval” üzenetet ad | A tenantban a felhasználói hozzájárulás tiltva van | Egy rendszergazda a portálon: *Enterprise applications → <projekt>-<env>-argocd → Permissions → Grant admin consent* |
| Application: *SyncError … the server could not find the requested resource* / *no matches for kind ClusterIssuer* | A CRD még nem létezik (pl. a cert-manager még települ) | Nincs teendő: a retry néhány percen belül megoldja. Ha 10 próbálkozás után is áll, *SYNC* a felületen |
| Application: *application destination … is not permitted in project* | A cél-namespace vagy a forrásrepó nincs engedélyezve a projektben | product: a platform namespace-ek tiltottak; új forrásrepó a projektbe pull requesttel |
| Application tartósan *OutOfSync*, de minden működik | Egy controller / webhook utólag módosítja az objektumot | Az eltérést a felület *DIFF* nézete mutatja; `ignoreDifferences` az Application-be |
| Egy Application törlése „beragad” (*Deleting*) | A finalizer megvárja, hogy az Argo CD törölje az erőforrásokat; ha az Argo CD már nem fut, senki nem veszi le a finalizert | `kubectl -n argocd patch application <név> --type merge -p '{"metadata":{"finalizers":null}}'` (csak ha az erőforrások valóban törölhetők) |
| Az apply *already exists – needs to be imported* hibát ad | Egy korábbi (kézi vagy 3. heti) erőforrás maradt meg, pl. egy NS-rekord a szülőzónában vagy egy Entra ID-csoport | A maradvány törlése, vagy `terraform import` |

---

## A. függelék – A pull request sablon

A pull request leírása automatikusan ez a sablon (`.github/pull_request_template.md`). Az igénylés adatai nem itt vannak, hanem a `tfvars` `request` blokkjában (B. függelék): így minden adat egy helyen van, és mindig tudom, hol keressem. A sablon csak egy rövid leírást és a review-listát tartalmazza.

````markdown
<!--
Környezetigénylés / -módosítás / platformváltozás.

Az igénylés MINDEN adata (igénylő, csapat, indoklás, jóváhagyó, lejárat,
tagok, méret) a terraform/environments/<env>.tfvars fájlban van, a `request`
blokkban – itt nem kell megismételni. A Terraform ellenőrzi (validation), és a
plan-ben is látszik (terraform_data.request).
Útmutató: dokumentacio/kornyezetigenyles.md, 3. fejezet.
-->

## Röviden

<!-- Egy-két mondat: mit változtat ez a pull request (pl. "Új dev környezet", "dev meghosszabbítása", "Argo CD bevezetése"). -->

---

### Platform engineer (review)

- [ ] A `Terraform Plan` ellenőrzés zöld, és a plan **csak** a kért környezetet / változást érinti (csere: `-/+` nincs)
- [ ] A `request` blokk kitöltve, az indoklás és a lejárat (max. 3 hónap) rendben
- [ ] Új környezetnél: a `vnet_address_space` / `node_subnet_prefix` szabad, át nem fedő tartomány; a kvóta elég
- [ ] Merge után: a sandbox (`sbx`) apply-ja sikeres, ott minden rendben (Argo CD: *Synced* / *Healthy*)
- [ ] Csak ezután: a továbbvitel jóváhagyva (*Review deployments* / `scripts/jovahagyas.sh`), az apply sikeres
- [ ] Az Argo CD-be Entra ID-val be lehet lépni, átadó üzenet elküldve
````

---

## B. függelék – A környezet tfvars sablonja

`terraform/environments/_sablon.tfvars.example` – a `.example` végződés miatt a pipeline nem tekinti környezetnek.

```hcl
# =============================================================================
# Környezetigénylés – sablon
# Másold le environments/<env>.tfvars néven, töltsd ki, és nyiss vele pull
# requestet (lásd: dokumentacio/kornyezetigenyles.md, 3. fejezet).
# =============================================================================

project_name = "<projekt>"   # kisbetű, szám, kötőjel; max. 15 karakter
env_name     = "<env>"       # = a fájl neve, pl. dev
expires      = "ÉÉÉÉ-HH-NN"  # lejárat, max. 3 hónap

# Az igénylés adatai (kötelező; külön űrlap nincs, minden itt van)
request = {
  requester = "<a te UPN-ed>"                 # az igénylő Entra ID UPN-je
  team      = "<csapat>"
  reason    = "<mire kell a környezet, pár mondatban>"
  approver  = "<költséghely / jóváhagyó vezető>"
  # size_reason = "<csak egyedi méretnél: miért kell nagyobb gép / több node>"
}

# A platform engineer tölti ki (a következő szabad /12):
vnet_address_space = "10.x.0.0/12"
node_subnet_prefix = "10.x.0.0/24"

# Hozzáférés: név => Entra ID UPN (userPrincipalName)
platform_admins = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
platform_admin_service_principals = {
  github-actions = "github-repos"
}
developers = {
  # vezeteknev = "upn@tenant.onmicrosoft.com"
}
readers = {
  # vezeteknev = "upn@tenant.onmicrosoft.com"
}

# Opcionális (csak indoklással):
# node_vm_size = "Standard_D2as_v5"
# node_count   = 1
# argocd_admin_enabled = false   # az Argo CD helyi admin fiókja (vészhelyzetre)
```

Példa: a `dev` környezet kitöltve (`terraform/environments/dev.tfvars`):

```hcl
# =============================================================================
# A(z) project-x dev környezet bemenetei (az igénylés adatai: request)
# Workspace: dev   –   a fájl neve, az env_name és a workspace neve egyezik
# =============================================================================

project_name = "project-x"
env_name     = "dev"
expires      = "2027-02-21"

# Az igénylés (a korábbi igénylőlap helyett: minden egy helyen, a Terraform
# ellenőrzi és a state-ben is rögzíti – terraform_data.request)
request = {
  requester = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
  team      = "Project X"
  reason    = "Közös fejlesztői környezet a Project X csapatnak; az alkalmazásainkat Argo CD-vel, a product projektbe telepítjük."
  approver  = "Cubix Platform Engineering kurzus"
}

# Hálózat: környezetenként saját, át nem fedő /12
vnet_address_space = "10.240.0.0/12"
node_subnet_prefix = "10.240.0.0/24"

# Hozzáférés: ember által olvasható név => Entra ID UPN
# (az object ID-t a Terraform keresi ki, lásd entra.tf)
platform_admins = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
platform_admin_service_principals = {
  github-actions = "github-repos" # a pipeline identitása: a Helm-telepítéshez kell a cluster-admin jog
}
developers = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
readers = {
  vighsandor = "platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"
}
```
