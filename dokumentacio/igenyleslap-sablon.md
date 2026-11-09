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
