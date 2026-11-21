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
