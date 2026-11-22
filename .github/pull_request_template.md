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
