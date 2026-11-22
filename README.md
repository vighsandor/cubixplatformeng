# Cubix Platform Engineering – Project X miniplatform

**5. hét: Argo CD alapok** (tag: `week5-argocd-basics`, fő ág: `platformeng-w3`)

A Project X fejlesztői pull requesttel igényelnek környezetet. A GitHub Actions pipeline pull requestre `fmt` + `validate` + `plan` lépést futtat, a fő ágra merge után `apply`-t. A Terraform felépíti az Azure- és Entra ID-erőforrásokat, és telepíti az **Argo CD**-t. A Kubernetesen belüli komponenseket (Traefik, External DNS, cert-manager, ClusterIssuer, demóalkalmazás) a Terraform által létrehozott **Argo CD Application-ök** telepítik, és az Argo CD folyamatosan a kívánt állapotban tartja őket. Az Argo CD-be Entra ID-fiókkal lehet belépni, titok nélkül.

## Leadott anyagok

| Elvárás | Hol található |
|---|---|
| Frissített környezetigénylési leírás | [`dokumentacio/kornyezetigenyles.md`](dokumentacio/kornyezetigenyles.md) (5.0) |
| A Helm-telepítések Argo CD Application-ökké alakítva | [`terraform/argocd.tf`](terraform/argocd.tf) (`helm_release.argocd_app`), a komponensek leírása: [`ingress.tf`](terraform/ingress.tf), [`external-dns.tf`](terraform/external-dns.tf), [`cert-manager.tf`](terraform/cert-manager.tf), [`demo-app.tf`](terraform/demo-app.tf) |
| `platform` / `product` projekt minden alkalmazáshoz | [`terraform/argocd.tf`](terraform/argocd.tf) (`helm_release.argocd_projects`): platformkomponensek → `platform`, demóalkalmazás → `product` |
| AutoSync és finalizer minden alkalmazáson | `syncPolicy.automated` (prune, selfHeal, retry) és `resources-finalizer.argocd.argoproj.io` |
| Terraform-szintű függőség az Argo CD-től és a projektektől | `depends_on = [helm_release.argocd, helm_release.argocd_projects]` minden Application-ön |
| Entra ID-belépés az Argo CD-be | [`terraform/argocd.tf`](terraform/argocd.tf): Entra ID-alkalmazás, workload identity (nincs client secret), RBAC a környezet csoportjai alapján |
| Pull request, amely a `dev` környezetet igényli | a repó *Pull requests* fülén: „Környezetigénylés: project-x dev (5. hét)” |
| A segédscript alapján az erőforrások listája | [`kimenetek/segedscript-kimenet-sbx.md`](kimenetek/segedscript-kimenet-sbx.md) (a script: [`segedscript/`](segedscript), futtatója: [`scripts/segedscript-futtatas.sh`](scripts/segedscript-futtatas.sh)) |

## A 4. heti visszajelzések alapján változott

- **Nincs külön igénylőlap.** Az igénylés minden adata (igénylő, csapat, indoklás, jóváhagyó, lejárat, tagok) a környezet `tfvars` fájljában van (`request` blokk). A Terraform ellenőrzi ([`common.tf`](terraform/common.tf): `validation`), és a `terraform_data.request` a state-ben is rögzíti. A PR-sablon csak egy rövid leírás és a review-lista.
- **Lépcsőzetes apply.** Merge után először csak a sandbox (`sbx`) frissül; a többi környezet csak annak sikere után, kézi jóváhagyással ([`terraform.yml`](.github/workflows/terraform.yml): `apply-first` → `apply-promote`, GitHub environment: `promotion`; jóváhagyás: [`scripts/jovahagyas.sh`](scripts/jovahagyas.sh)).
- **Bootstrap:** maradtak a scriptek (újrafuttathatók). A dokumentáció 4.2 pontja leírja, hogy élesben ez egy külön, a projekten kívüli Terraform-kód lenne.

## Korábbi hetek

| Hét | Tag | Tartalom |
|---|---|---|
| 3. | `week3-iac` | Terraform, környezetenként külön kód |
| 4. | `week4-pipeline-tf` | GitHub Actions pipeline, workspace-ek, ruleset, a Kubernetes-komponensek Helmmel Terraformból |
| 5. | `week5-argocd-basics` | Argo CD, Application-ök Terraformból, Entra ID-belépés |

## Gyorsindítás

```bash
az login && ./bootstrap/01-azure-github-identity.sh        # egyszer (5. héttől: + Application Developer)
gh auth login && ./bootstrap/02-github-repo.sh secrets     # egyszer: repo secretek
./bootstrap/02-github-repo.sh default-branch               # egyszer: alapértelmezett ág
./bootstrap/02-github-repo.sh environments                 # egyszer: jóváhagyás a sandbox utáni környezetekhez
./bootstrap/02-github-repo.sh ruleset                      # egyszer, az első sikeres futás után
```

Ezután egy környezet igénylése: ág, `terraform/environments/<env>.tfvars` a sablonból, pull request (lásd a leírás 3. fejezetét). Lebontás: `./scripts/lebontas.sh <env>`.
