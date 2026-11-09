# Cubix Platform Engineering – Project X miniplatform

**3. hét – Infrastructure as Code** (`platformeng-w3` ág, `week3-iac` tag)

Az eddig ClickOps-szal felépített infrastruktúra Terraformban: resource groupok, hálózat, AKS, managed identityk, workload identity federation, DNS-alzóna és -delegáció, Entra ID-csoportok, tagságok és szerepkörök – a `sbx` és a `dev` környezetre, kóddal és state-tel együtt. A Kubernetesen belüli komponensek (Traefik, External DNS, cert-manager, demóalkalmazás) ezen a héten szándékosan kézi, Helm-es lépések.

## Beadandó

| Elem | Hol |
|---|---|
| A környezetigénylési leírás (frissítve, 3.0) | [`dokumentacio/kornyezetigenyles.md`](dokumentacio/kornyezetigenyles.md) |
| Igénylőlap-sablon | [`dokumentacio/igenyleslap-sablon.md`](dokumentacio/igenyleslap-sablon.md) |
| Terraform-kód – sandbox | [`terraform/sbx/`](terraform/sbx/) |
| Terraform-kód – dev | [`terraform/dev/`](terraform/dev/) |
| Terraform state – sandbox / dev | [`terraform/sbx/state/`](terraform/sbx/state/), [`terraform/dev/state/`](terraform/dev/state/) |
| Segédscript (oktatói, változatlan) | [`segedscript/3-iac-7-homework.sh`](segedscript/3-iac-7-homework.sh) |
| Segédscript- és curl-kimenetek | [`kimenetek/`](kimenetek/), és beillesztve a leírás C. függelékébe |

## Használat

Előfeltétel: `az`, `terraform` (≥ 1.4), `kubectl`, `kubelogin`, `helm`, `curl`; `az login`.

```bash
./scripts/sbx-letrehozas.sh
./scripts/dev-letrehozas.sh

./scripts/sbx-lebontas.sh
./scripts/dev-lebontas.sh
```

A scriptek a `plan` után megerősítést kérnek; `AUTO_APPROVE=1` esetén nem kérdeznek.

## Felépítés

```
terraform/<env>/   provider.tf, common.tf, network.tf, aks.tf, dns.tf, outputs.tf, terraform.tfvars, state/
k8s/               ClusterIssuer, External DNS values-sablon
scripts/           kozos.sh, kornyezet-letrehozas.sh, kornyezet-lebontas.sh, <env>-letrehozas.sh, <env>-lebontas.sh, kimenetek-beillesztese.sh
segedscript/       az oktatói segédscript
kimenetek/         a segédscript és a curl kimenetei
dokumentacio/      a környezetigénylési leírás és az igénylőlap
```
