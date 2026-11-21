# Környezetigénylési folyamat – Project X miniplatform (pipeline + Terraform)

Ebben a dokumentumban leírom, hogyan működik nálam az új futtatókörnyezetek igénylése és kiszolgálása. Két nézőpontot rögzítek:

1. **A fejlesztői oldal:** mit kell tennie egy fejlesztőnek, ha új környezetet szeretne kapni (3. fejezet).
2. **Az üzemeltetői oldal:** mit csinálok én platform engineerként, amikor beérkezik egy igénylés (4. fejezet).

A folyamat alapja a `project-x` **sandbox** (`sbx`) és **dev** környezet. Ezeket először kézzel (ClickOps) építettem fel, aztán Terraform-kódba ültettem át, a 4.0-s verzióban pedig **a kód már csak GitHub Actions pipeline-ból fut**. Egy környezet igénylése ma egy **pull request**: a fejlesztő leírja a kívánt környezetet, a pipeline megmutatja, mi fog történni, és a merge után létre is hozza.

**Az alap DNS-zónám:** `vighsandor.az.cubix-pe.hu`. Minden környezet ez alá kap saját alzónát.

**A repó:** <https://github.com/vighsandor/cubixplatformeng>. A fő ág a `platformeng-w3`, a 4. heti állapot tagje `week4-pipeline-tf`.

### Változásnapló

| Verzió | Tartalom |
|---|---|
| 1.0 | ClickOps-alapinfrastruktúra: AKS, Traefik, Azure DNS alzóna kézi A rekordokkal, cert-manager, Let's Encrypt |
| 2.0 | Entra ID-integráció és automatikus DNS: jogosultság csak Entra ID-csoportoknak; External DNS managed identityvel és workload identity federationnel, titok nélkül |
| 3.0 | Infrastructure as Code: az Azure- és Entra ID-erőforrások Terraformból, környezetenként külön kódkönyvtárban és state-tel; a Kubernetesen belüli rész még kézi Helm |
| **4.0** | **Pipeline és teljes IaC.** A Terraform GitHub Actionsből fut (pull requestre `fmt` + `validate` + `plan`, a fő ágra merge után `apply`), a GitHub titok nélkül, workload identity federationnel jelentkezik be az Azure-ba. A fő ágat ruleset védi. **A környezetigénylés egy pull request** (3. fejezet). A Kubernetesen belüli komponenseket (Traefik, External DNS, cert-manager, ClusterIssuer, demóalkalmazás) is a Terraform telepíti. Egy kód, több környezet: **Terraform workspace-ek** és környezetenkénti `tfvars`, workspace-védelemmel. Az Entra ID-csoportok külön fájlba kerültek, a tagokat név és UPN alapján adom meg (a Terraform keresi ki az object ID-t), és magam is tagja vagyok minden csoportnak, hogy a jogosultságok működés közben is látszódjanak. |

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
| Gépi identitás | Workload identity federation: a clusterben futó platformkomponensek és a pipeline is titkos kulcs nélkül, managed identityvel érik el az Azure-t |
| Önkiszolgálás | Környezetet pull requesttel lehet igényelni; a pipeline a merge után emberi kattintgatás nélkül felépíti |
| Reprodukálhatóság | Minden környezet ugyanabból a Terraform-kódból jön létre; két környezet között csak a `tfvars` fájl és a workspace különbözik |

Az eredmény: a fejlesztő egyetlen Ingress-erőforrással **névvel elérhető, TLS-sel védett** végpontot kap, emberi beavatkozás nélkül.

### 1.2 Megkötések és a mögöttük álló döntéseim

| Terület | Szabály | Indoklás |
|---|---|---|
| Régió | Sweden Central | Itt van biztosított kvótám, és minden környezet egy helyen fut. |
| Méret | 1 node, `Standard_D2as_v5` (2 vCPU, 8 GiB RAM) | A kvóta szűkös: a Standard DASv5 családra 4 vCPU, a régióra összesen 8 vCPU jut. Nagyobb gépet csak indoklással adok. |
| Frissítés | Az automatikus frissítés ki van kapcsolva | Rövid életű, eltakarítandó környezetekről van szó; a verziót én tartom kézben (Terraform-változó). |
| **Változtatás** | **Minden változás pull requesten keresztül megy, és csak a pipeline módosítja az infrastruktúrát** | A fő ágra közvetlenül senki nem pusholhat (én sem). Minden változáshoz tartozik egy plan, egy review és egy futási napló: visszakövethető, ki, mit, mikor és miért változtatott (auditálhatóság). A portálon kézzel nem módosítok, mert az driftet okoz. |
| Jogosultság | Jogot csak Entra ID-csoport kap, személy soha. Egyetlen kivétel a pipeline gépi identitása (4.3). | Csoportokkal a jogosultságkezelés skálázható és követhető. Ha valaki elhagyja a projektet, elég kivenni a csoportból (egy sor törlése a `tfvars`-ból). |
| Gépi hozzáférés | Titkos kulcsot nem használok; a gépi identitás managed identity, federated credentiallel | A lejáró, kézzel forgatandó titkok kezelése hibalehetőség és biztonsági kockázat. A GitHub repóban nincs Azure-jelszó, csak azonosítók. |
| Legkisebb jogosultság | Az External DNS identitása csak *DNS Zone Contributor* szerepkört kap, és csak a saját környezete alzónáján | Ha egy környezet komponense kompromittálódik, más környezet DNS-éhez akkor sem fér hozzá. |
| DNS | A hosztnevek automatikusan jönnek létre, de csak a környezet saját alzónáján belül | Az External DNS `domainFilters` beállítása a zónán kívüli hosztneveket figyelmen kívül hagyja. |
| TLS | Let's Encrypt **staging** végpont | Az éles Let's Encrypt ugyanarra a névre nagyjából heti 5 tanúsítványt ad ki; a stagingnél ez a korlát jóval magasabb, így szabadon lehet újraépíteni. Ára, hogy a böngésző „nem biztonságos” figyelmeztetést ad. |
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

### 2.3 Entra ID-csoportok (környezetenként, `entra.tf`)

| Csoport | Minta | Tagok (`tfvars`) | Szerepkörök a clusteren |
|---|---|---|---|
| Platformadminok | `<projekt>-<env>-platform-admins` | `platform_admins` (én) + `platform_admin_service_principals` (a pipeline: `github-repos`) | Azure Kubernetes Service **RBAC Cluster Admin**, **Cluster User Role**; a pipeline identitása ezen felül közvetlenül is RBAC Cluster Admin (4.3) |
| Fejlesztők (írás) | `<projekt>-<env>-developers` | `developers` | Azure Kubernetes Service **RBAC Writer**, **Cluster User Role** |
| Olvasók | `<projekt>-<env>-readers` | `readers` | Azure Kubernetes Service **RBAC Reader**, **Cluster User Role** |

A tagokat **név → UPN** párokkal adom meg (pl. `vighsandor = "…@….onmicrosoft.com"`), az object ID-t a Terraform keresi ki (`data "azuread_user"`). A plan így ember által olvasható nevet mutat (`azuread_group_member.env["developers/vighsandor"]`), és a `tfvars` önmagában is dokumentálja, ki milyen jogot kapott. Magam mindhárom csoportnak tagja vagyok, hogy a jogosultságok működését (írás, olvasás) a saját fiókommal is ellenőrizni tudjam.

### 2.4 Kubernetes-objektumok (Terraform `helm_release`-ek)

| Komponens | Namespace | Helm release | Chart (verzió) |
|---|---|---|---|
| Ingress controller | `ingress-controller` | `traefik` | `traefik` (41.2.0) |
| DNS-automatizmus | `external-dns` | `external-dns` | `external-dns` (1.20.0) |
| Tanúsítványkezelés | `cert-manager` | `cert-manager` | `cert-manager` (v1.19.4) |
| Let's Encrypt ClusterIssuer | `cert-manager` | `cluster-issuer` | `bedag/raw` (2.0.2) |
| Demóalkalmazás | `colors` | `colors` | `oci://docker.io/ecklm/colors-demo-app` |

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
6. Csatlakozol, telepíted az alkalmazásod
   (a DNS-név és a TLS-tanúsítvány automatikusan elkészül)
7. Módosítás, meghosszabbítás, megszüntetés: újabb pull request
```

### 3.2 1. lépés: készülj fel

1. Legyen **Entra ID-fiókod** a céges tenantban, és tudd a **UPN**-edet (userPrincipalName). Ezzel lépsz be a clusterbe, és ezzel veszlek fel a környezet csoportjaiba. A UPN-t így kérdezheted le: `az ad signed-in-user show --query userPrincipalName -o tsv`.
2. Legyen **GitHub-fiókod**, és olvasási jogod a `vighsandor/cubixplatformeng` repóhoz. Ha nincs, kérd tőlem.
3. Telepítsd a szükséges eszközöket: `git`, `az` (Azure CLI), `kubectl`, `kubelogin`, `helm`.
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
   - `developers` (írás) és `readers` (olvasás): `név = "UPN"` soronként;
   - a hálózati tartományt (`vnet_address_space`, `node_subnet_prefix`) hagyd a sablon szerint, azt én töltöm ki.

3. Commitold és pushold, majd nyiss pull requestet a **`platformeng-w3`** ágra:

   ```bash
   git add terraform/environments/<env>.tfvars
   git commit -m "Környezetigénylés: <projekt> <env>"
   git push -u origin igenyles/<projekt>-<env>
   ```

   A GitHubon a **Compare & pull request** gombbal nyithatod meg. A pull request leírása automatikusan az **igénylőlap**, ezt töltsd ki ([A. függelék](#a-függelék--az-igénylőlap-pull-request-sablon)).

   > Ha nincs írási jogod a repóhoz, forkold, és onnan nyiss pull requestet; vagy küldd el nekem a kitöltött `tfvars` fájlt és az igénylőlapot, és én nyitom meg a pull requestet helyetted.

### 3.4 3. lépés: kövesd a pull requestet

1. A pull requesten azonnal elindul a **Terraform** pipeline. Környezetenként lefut egy `Terraform Plan (<env>)` job, a pull request alján pedig a `Terraform Plan` ellenőrzés mutatja az összesített eredményt.
2. A job összefoglalójában (*Actions* → a futás → *Summary*) látod, mit hozna létre a plan a környezetedhez. Új környezetnél ez körülbelül 35 létrehozandó erőforrás, a többi környezetnél pedig `No changes`.
3. **2 munkanapon belül** átnézem: ha kell, kiegészítem (hálózati tartomány), kérdezek, vagy jóváhagyom.
4. A merge után a pipeline `Terraform Apply (<env>)` jobja felépíti a környezetet (kb. 10–15 perc). A végén **átadó üzenetet** küldök a csatlakozás adataival; ugyanezek a futás összefoglalójában (`terraform output`) is ott vannak.

### 3.5 4. lépés: csatlakozz a clusterhez

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

Az alkalmazás Ingress-erőforrásán két dolgot kell beállítanod:

1. A **host** a környezeted alzónáján belül legyen: `<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu`.
2. Az Ingress kapja meg a **`cert-manager.io/cluster-issuer: letsencrypt`** annotációt.

```bash
helm upgrade --install --namespace=<app> --create-namespace <app> <chart-referencia> \
    --set ingress.host=<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu \
    --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt
```

Ezután automatikusan: az **External DNS** 1–2 percen belül létrehozza az A rekordot, a **cert-manager** tanúsítványt kér, és néhány perc múlva az alkalmazás elérhető a `https://<app>.<projekt>.<env>.vighsandor.az.cubix-pe.hu` címen.

> - **Zónán kívüli hosztnév nem működik:** az External DNS figyelmen kívül hagyja.
> - **Az Ingress törlésekor a DNS-rekord is törlődik.**
> - Az `ingress-controller`, `external-dns` és `cert-manager` namespace a platform része, és a Terraform kezeli: ha módosítod, a következő pipeline-futás visszaírja.

### 3.7 Módosítás, meghosszabbítás, megszüntetés

Mindegyik ugyanúgy megy, mint az igénylés: egy pull request a környezeted `tfvars` fájljára.

| Igény | Mit módosítasz a `terraform/environments/<env>.tfvars`-ban |
|---|---|
| Új csapattag / kilépő tag | sor hozzáadása / törlése a `developers` vagy `readers` térképben |
| Meghosszabbítás | `expires` |
| Más méret | `node_vm_size`, `node_count` (indoklással a PR-ban) |
| Megszüntetés | jelezd a PR-ban „Megszüntetés” típussal; a lebontást én végzem (4.8) |

Új hosztnévhez nem kell pull request: elég egy Ingress (3.6).

---

## 4. Üzemeltetői folyamat: pipeline és Terraform

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
- A „folyamatosan figyelő” Terraform-funkciók (drift detection, automatikus újrapróbálás) fizetős termékben (Terraform Cloud) vannak. Ezeket a Kubernetesen belül később egy deklaratív, folyamatosan egyeztető eszköz (Argo CD) adja majd.

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
                                            Terraform Apply (env) ×N ──────► ├─ Blob Data Contributor a state-en
                                            (pontosan a plan-t alkalmazza)   ├─ Groups Administrator (Entra)
                                                                             ├─ Directory Readers (Entra)
                                                                             └─ AKS RBAC Cluster Admin (közvetlenül) ->
                                                                                (a Helm-telepítésekhez)
```

**A repó felépítése:**

```
.
├── .github/
│   ├── workflows/terraform.yml          # plan pull requestre, apply a fő ágra
│   ├── workflows/terraform-destroy.yml  # egy környezet lebontása kézi indítással
│   └── pull_request_template.md         # az igénylőlap (A. függelék)
├── terraform/                           # EGY kód minden környezetre
│   ├── provider.tf      # backend (state), providerek: azurerm, azuread, helm, time
│   ├── common.tf        # közös változók, nevek, tagek, workspace-védelem
│   ├── network.tf       # VNet, alhálózat
│   ├── aks.tf           # AKS, a cluster identitása, a csoportok jogai, RBAC-várakozás
│   ├── entra.tf         # Entra ID-csoportok és tagjaik (név -> UPN -> object ID)
│   ├── dns.tf           # alzóna, NS-delegáció
│   ├── external-dns.tf  # External DNS: identitás, federáció, jog és Helm-telepítés
│   ├── ingress.tf       # Traefik
│   ├── cert-manager.tf  # cert-manager és a Let's Encrypt ClusterIssuer
│   ├── demo-app.tf      # colors demóalkalmazás (füstteszt)
│   ├── outputs.tf
│   └── environments/
│       ├── sbx.tfvars, dev.tfvars, ...  # környezetenként egy fájl = egy igénylés
│       └── _sablon.tfvars.example       # sablon az új igénylésekhez
├── bootstrap/           # egyszeri beállítás (pipeline-identitás, secretek, ruleset)
├── scripts/tf.sh        # helyi futtatás hibakereséshez
└── dokumentacio/        # ez a leírás
```

### 4.2 Egyszeri beállítás: a pipeline Azure-identitása és a GitHub repo

Ezt egyszer, a platform indulásakor csinálom meg, a saját fiókommal. Mindkét script újrafuttatható: ami már megvan, azt nem hozza létre újra.

**1. A pipeline identitása** – `bootstrap/01-azure-github-identity.sh`

```bash
az login
./bootstrap/01-azure-github-identity.sh
```

| Mit hoz létre | Miért |
|---|---|
| `github-repos` managed identity a `course-baseline`-ban | a pipeline ezzel az identitással dolgozik az Azure-ban; nincs jelszava |
| 4 federated credential: a `platformeng-w3` ágra és a pull requestekre, mindkettő az új (módosíthatatlan azonosítós: `repo:vighsandor@<id>/cubixplatformeng@<id>:…`) és a régi (`repo:vighsandor/cubixplatformeng:…`) subject-formátumban | a GitHub OIDC-tokenjét az Entra ID csak akkor fogadja el, ha a `sub` mező pontosan egyezik; a GitHub a repó beállításától függően az egyik vagy a másik formát küldi, így mindkettőt felveszem |
| **Owner** az előfizetésen | erőforrásokat hoz létre, és szerepköröket oszt ki (pl. a csoportoknak az AKS-en) |
| **Storage Blob Data Contributor** a `platencbvighsandor` storage accounton | a state olvasása, írása, zárolása (az Owner adat-jogot nem ad) |
| **Groups Administrator** Entra ID-szerepkör | Entra ID-csoportok létrehozása és a tagság kezelése |
| **Directory Readers** Entra ID-szerepkör | a felhasználók kikeresése UPN alapján (`data "azuread_user"`) és a saját service principalja kikeresése |

> Az Azure-szerepkörök (Owner, Blob Data Contributor) és az Entra ID-szerepkörök (Groups Administrator, Directory Readers) két külön világ: az előbbiek az Azure-erőforrásokra, az utóbbiak a címtárra (felhasználók, csoportok) adnak jogot. Az Entra ID-szerepkörök kiosztásához Global Administrator vagy Privileged Role Administrator jog kell.

**2. A GitHub repo** – `bootstrap/02-github-repo.sh` (a `gh` CLI-vel, a repo adminjaként)

```bash
gh auth login
./bootstrap/02-github-repo.sh secrets          # AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
./bootstrap/02-github-repo.sh default-branch   # a platformeng-w3 legyen az alapértelmezett ág
# ... az első sikeres pipeline-futás után:
./bootstrap/02-github-repo.sh ruleset
```

- **Secretek:** a három érték azonosító, nem jelszó. Secretként azért tárolom őket, hogy ne kelljen a workflow-ba égetni, és máshol is ugyanígy használható legyen.
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

**A Kubernetesen belüli rész is Terraform.** A Helm providerrel a Terraform ugyanabban a futásban, ugyanabból a kódból telepíti a Traefiket, az External DNS-t, a cert-managert, a ClusterIssuert és a demóalkalmazást. Ennek fő előnye, hogy **a Terraform-erőforrások közvetlenül elérhetők**: az External DNS values-ába a managed identity Client ID-ja, a zóna neve és a resource groupok neve közvetlenül az erőforrásokból kerül, nincs kézi másolás vagy sablonkitöltés. (A másik út, a Helm-parancsok a pipeline-ban, azt jelentené, hogy minden Helm-műveletet és -kapcsolót a pipeline-ban újra kellene implementálni.)

- **Bejelentkezés a clusterbe:** az AKS-en nincsenek helyi fiókok, ezért a Helm provider a `kubelogin`-nal kér tokent az Azure CLI bejelentkezéséből (`--login azurecli`). Helyben ez a saját fiókom, a pipeline-ban a `github-repos` identitás; ezért a pipeline identitásának (`platform_admin_service_principals`) cluster-admin jog kell. A pipeline identitása tagja a platform-admins csoportnak, és **közvetlenül is megkapja** az *Azure Kubernetes Service RBAC Cluster Admin* szerepkört (`azurerm_role_assignment.aks_pipeline`). Erre azért van szükség, mert a pipeline az AKS-tokent a futás elején kéri, amikor egy új környezet csoportjának még nem tagja. A token `groups` claimjéből így hiányzik a csoport, és a csoporton keresztüli jog csak a következő futásban működne. A közvetlen szerepkör-hozzárendelést az Azure szerveroldalon értékeli ki. Ez a „jogot csak csoport kap” szabály egyetlen, tudatos kivétele, és egy gépi identitásra vonatkozik, nem személyre.
- **A ClusterIssuer** nem chart, hanem egy sima Kubernetes-erőforrás. A Helm provider nem tud nyers manifestet telepíteni, a Kubernetes provider pedig a CRD-k miatt nehézkes, ezért a `bedag/raw` „csomagoló” chartot használom: a chart a values-ban kapott erőforrásokat telepíti.
- **Várakozás az RBAC-ra:** új környezetnél a csoporttagság és az AKS-szerepkör néhány perc alatt lép életbe. A Helm-telepítések egy `time_sleep` (180 s) után indulnak, különben az első futás 403-at kapna.
- **Sorrend:** a függőségek miatt a Terraform maga rendezi: AKS → szerepkörök → várakozás → Traefik, External DNS, cert-manager → ClusterIssuer → demóalkalmazás.

**Rögzített verziók:** Terraform ≥ 1.5, `azurerm` 5.3.0, `azuread` 3.9.0, `helm` 3.2.0, `time` 0.14.2, és minden chart pontos verzióval.

**A portálbeállítások Terraform-megfelelői** (a ClickOps-os kiindulópontból):

| ClickOps (portál) | Terraform |
|---|---|
| Pricing tier: Free; Automatic upgrade: Disabled; Node security channel: None | `sku_tier = "Free"`, `automatic_upgrade_channel = null`, `node_os_upgrade_channel = "None"` |
| Node pool `system`, `Standard_D2as_v5`, Manual, 1 node | `node_provisioning_profile { mode = "Manual" }`, `default_node_pool { … }` |
| Azure CNI Overlay, saját VNet, user assigned identity | `network_profile { network_plugin_mode = "overlay" }`, `vnet_subnet_id`, `identity { type = "UserAssigned" }` |
| Entra ID + Azure RBAC, Local accounts: Disabled | `azure_active_directory_role_based_access_control { azure_rbac_enabled = true }`, `local_account_disabled = true` |
| OIDC + Workload Identity | `oidc_issuer_enabled = true`, `workload_identity_enabled = true` |
| „Child of an existing zone” | `azurerm_dns_ns_record.delegation` a szülőzónában |
| `helm upgrade --install …` (Traefik, External DNS, cert-manager, colors) | `helm_release` |
| `kubectl apply -f cluster-issuer.yaml` | `helm_release` a `bedag/raw` charttal |

### 4.4 A pipeline működése (`.github/workflows/terraform.yml`)

| Esemény | Mi fut | Eredmény |
|---|---|---|
| **pull request** a `platformeng-w3` ágra | `Terraform Plan (<env>)` minden környezetre, majd az összesítő `Terraform Plan` | a PR-on látszik, mit változtatna a merge; a ruleset ennek zöld állapotát várja |
| **push** a `platformeng-w3` ágra (= merge) | újra plan, majd `Terraform Apply (<env>)` minden környezetre | a változás élesedik |
| kézi indítás (*Run workflow*) | plan (és a fő ágon apply) | drift-ellenőrzés, újrafuttatás |

**A plan job lépései:** checkout → Azure-bejelentkezés (OIDC) → Terraform és kubelogin telepítése → `terraform fmt -check` → `init` → `workspace select -or-create <env>` → `validate` → `plan -var-file=… -out=tfplan` → a plan összefoglalója a futás *Summary* oldalára → a plan feltöltése artifactként.

**Az apply job** letölti **ugyanannak a futásnak** a plan-jét, és pontosan azt alkalmazza (`terraform apply tfplan`), nem számol újat. Így az élesedik, amit a napló mutat. A merge után a plan újra lefut, mert a pull request plan-je a merge előtti állapotra készült.

**Környezetek felderítése:** az első job kilistázza a `terraform/environments/*.tfvars` fájlokat, és ebből lesz a mátrix. **Új környezet = új tfvars fájl**, a workflow-t nem kell módosítani.

**Párhuzamosság és zárolás:** a környezetek egymástól függetlenül, párhuzamosan futnak; egy környezeten egyszerre csak egy apply futhat (`concurrency`), és a plan/apply legfeljebb 10 percig vár a state-zárolásra (`-lock-timeout=10m`).

### 4.5 Egy igénylés kiszolgálása (review → merge → apply)

1. **Beérkezik a pull request.** Ellenőrzöm az igénylőlapot: típus, igénylő, lejárat, indoklás.
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
6. **Merge.** A pipeline `Terraform Apply (<env>)` jobja létrehozza / módosítja a környezetet.
7. **Ellenőrzés és átadás** (4.6).

### 4.6 Ellenőrzés és átadás

1. Az apply futás *Summary* oldalán a `terraform output`: cluster, DNS-zóna, csoportok, demó URL, csatlakozási parancsok.
2. Csatlakozom, és ellenőrzöm a láncot:

   ```bash
   az aks get-credentials -g <projekt>-<env>-aks -n <projekt>-<env> --overwrite-existing
   kubelogin convert-kubeconfig -l azurecli
   kubectl get nodes
   kubectl get pods,ingress -A
   kubectl get clusterissuer,certificate -A
   curl -k https://colors.<projekt>.<env>.vighsandor.az.cubix-pe.hu   # <title>Rollouts Demo</title>
   ```

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

   Csatlakozás:
     az aks get-credentials -g <projekt>-<env>-aks -n <projekt>-<env> --overwrite-existing
     kubelogin convert-kubeconfig -l azurecli

   Lejárat: <dátum>. Módosítás, meghosszabbítás: pull request a környezeted tfvars fájljára.
   ```

### 4.7 Módosítás és drift

- **Minden módosítás pull request** a `tfvars`-ra (tagok, lejárat, méret) vagy a kódra (platformváltozás). A kódváltozás minden környezet plan-jében megjelenik, így látom, hogy melyiket hogyan érinti.
- **Drift-gyanú esetén** kézzel indítok egy futást (*Actions* → *Terraform* → *Run workflow*, ág: `platformeng-w3`). A plan megmutatja az eltérést; a fő ágon az apply vissza is állítja a kódban leírt állapotot. Ha az eltérés jogos volt, előbb a kódot igazítom (pull request).

### 4.8 Megszüntetés (lebontás)

A lebontás szándékosan **nem automatikus**, és két lépésből áll:

1. **Lebontás a pipeline-nal:** *Actions* → **Terraform destroy** → *Run workflow* (ág: `platformeng-w3`), `environment`: a környezet neve, `confirm`: még egyszer a neve. A workflow a `terraform destroy`-jal mindent töröl, amit a kód létrehozott: a Helm-telepítéseket, az AKS-t, a hálózatot, az identitásokat, a DNS-zónát és a delegációt, valamint az Entra ID-csoportokat és a tagságokat is.
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
| Az apply *already exists – needs to be imported* hibát ad | Egy korábbi (kézi vagy 3. heti) erőforrás maradt meg, pl. egy NS-rekord a szülőzónában vagy egy Entra ID-csoport | A maradvány törlése, vagy `terraform import` |

---

## A. függelék – Az igénylőlap (pull request sablon)

A pull request leírása automatikusan ez a sablon (`.github/pull_request_template.md`). A géppel feldolgozott rész a `tfvars` fájl, ez az emberi kontextus hozzá.

````markdown
<!--
Környezetigénylés / -módosítás – Project platform
Kitöltési útmutató: dokumentacio/kornyezetigenyles.md, 3. fejezet.
A géppel feldolgozott rész a terraform/environments/<env>.tfvars fájl ebben a
pull requestben; ez a leírás az emberi kontextus hozzá. A `[ ]` jelet `[x]`-re
cseréld a megfelelő sorban. A *-gal jelölt mezők kötelezők.
-->

## 1. Az igénylés típusa *

- [ ] Új környezet (új `terraform/environments/<env>.tfvars`)
- [ ] Módosítás (tagok, méret)
- [ ] Meghosszabbítás (`expires`)
- [ ] Megszüntetés
- [ ] Platformváltozás (a Terraform-kód módosítása – csak platform engineer)

## 2. Igénylő

| Mező | Érték |
|---|---|
| Név * | |
| Entra ID UPN * | |
| Csapat * | |
| Költséghely / jóváhagyó vezető * | |

## 3. Környezet

| Mező | Érték |
|---|---|
| Projekt * | |
| Környezet (`env_name`, = a tfvars fájl neve) * | |
| Mire használjátok? * | |
| Mikorra kell? * | |
| Lejárat (`expires`, max. 3 hónap) * | |

## 4. Hozzáférés

A tfvars `developers` (írás) és `readers` (olvasás) térképébe írd be a tagokat
`név = "UPN"` formában. Itt csak azt írd le, ha valami eltér a megszokottól.

## 5. Erőforrásméret

- [ ] Alapértelmezett: 1 node, 2 vCPU, 8 GiB RAM (`Standard_D2as_v5`)
- [ ] Egyedi (`node_vm_size` / `node_count` a tfvars-ban). Indoklás:

## 6. Megjegyzés

---

### Platform engineer tölti ki (review)

- [ ] A `Terraform Plan` ellenőrzés zöld, és a plan **csak** az igényelt környezetet érinti
- [ ] A `vnet_address_space` / `node_subnet_prefix` szabad, át nem fedő tartomány
- [ ] Kvóta ellenőrizve (DASv5 / régiós vCPU)
- [ ] A tagok UPN-jei léteznek (a plan kikereste őket)
- [ ] Merge után: a `Terraform Apply` sikeres, átadó üzenet elküldve
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
```

Példa: a `dev` környezet kitöltve (`terraform/environments/dev.tfvars`):

```hcl
# =============================================================================
# A(z) project-x dev környezet bemenetei (igénylés: lásd a pull requestet)
# Workspace: dev   –   a fájl neve, az env_name és a workspace neve egyezik
# =============================================================================

project_name = "project-x"
env_name     = "dev"
expires      = "2027-02-21"

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
