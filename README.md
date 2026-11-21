# Cubix Platform Engineering – Project X miniplatform

**4. hét: GitHub Actions pipeline és teljes Terraform** (tag: `week4-pipeline-tf`, fő ág: `platformeng-w3`)

A Project X fejlesztői pull requesttel igényelnek környezetet. A pipeline pull requestre `fmt` + `validate` + `plan` lépést futtat, a fő ágra merge után pedig `apply`-t. A Terraform az Azure- és Entra ID-erőforrások mellett a Kubernetesen belüli platformkomponenseket is telepíti (Traefik, External DNS, cert-manager, ClusterIssuer, demóalkalmazás). A környezetek egy kódból, Terraform workspace-ekkel és környezetenkénti `tfvars` fájlokkal jönnek létre.

## Leadott anyagok

| Elvárás | Hol található |
|---|---|
| Frissített környezetigénylési leírás | [`dokumentacio/kornyezetigenyles.md`](dokumentacio/kornyezetigenyles.md) (4.0) |
| Terraform futtatása GitHub Actionsből | [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) |
| Kubernetesen belüli erőforrások Terraformból (Helm) | [`terraform/ingress.tf`](terraform/ingress.tf), [`external-dns.tf`](terraform/external-dns.tf), [`cert-manager.tf`](terraform/cert-manager.tf), [`demo-app.tf`](terraform/demo-app.tf) |
| PR → `validate` + `plan` | a workflow `Terraform Plan (<env>)` jobjai és az összesítő `Terraform Plan` ellenőrzés |
| Ruleset a fő ágon (csak PR, kötelező plan, csak naprakész ág) | [`bootstrap/02-github-repo.sh`](bootstrap/02-github-repo.sh) `ruleset` |
| Merge → `apply` | a workflow `Terraform Apply (<env>)` jobjai |
| Környezetek szeparálása | Terraform workspace-ek + [`terraform/environments/`](terraform/environments), workspace-védelem a [`common.tf`](terraform/common.tf)-ben |
| A pipeline identitása (titok nélkül) | [`bootstrap/01-azure-github-identity.sh`](bootstrap/01-azure-github-identity.sh) |
| Igénylőlap | [`.github/pull_request_template.md`](.github/pull_request_template.md) |
| Igénylő pull requestek | a repó *Pull requests* fülén: a `dev` környezet igénylése (merge-ölve) és a `dev` meghosszabbítása (nyitva) |

## A 3. heti visszajelzések alapján változott

- Mindhárom csoportnak (platform-admins, developers, readers) tagja vagyok, így a jogosultságok működés közben is látszanak.
- A tagokat `név = "UPN"` térképpel adom meg, az object ID-t a Terraform keresi ki (`data "azuread_user"`).
- Az Entra ID-csoportok és a tagságok külön fájlba kerültek: [`terraform/entra.tf`](terraform/entra.tf).

## Gyorsindítás

```bash
az login && ./bootstrap/01-azure-github-identity.sh        # egyszer: a pipeline identitása
gh auth login && ./bootstrap/02-github-repo.sh secrets     # egyszer: repo secretek
./bootstrap/02-github-repo.sh default-branch               # egyszer: alapértelmezett ág
./bootstrap/02-github-repo.sh ruleset                      # egyszer, az első sikeres futás után
```

Ezután egy környezet igénylése: ág, `terraform/environments/<env>.tfvars` a sablonból, pull request (lásd a leírás 3. fejezetét).
