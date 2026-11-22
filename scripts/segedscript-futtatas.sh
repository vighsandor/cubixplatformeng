#!/usr/bin/env bash
# =============================================================================
# Az 5. heti segédscript (segedscript/5-argocd-basics-5-homework.sh) futtatása
# egy környezetre, a kimenet Markdownba gyűjtése (kimenetek/).
#
#   ./scripts/segedscript-futtatas.sh [env]        # alapértelmezés: sbx
#
# A segédscriptet változatlanul hagyom. A futtatáshoz egy ideiglenes másolatban
# csak a környezetfüggő neveket helyettesítem be:
#   <domain>                   -> a környezet DNS-zónája
#   project-x-hw-externaldns   -> project-x-<env>-externaldns (az én elnevezésem)
#   project-x-sbx              -> project-x-<env> (ha nem az sbx-et futtatom)
# Minden parancs kimenete (stdout + stderr) változtatás nélkül, kódblokkban
# kerül a Markdown-fájlba.
#
# Előfeltétel: az login (a felhasználóm platform-admins tag), kubelogin,
# kubectl, terraform. A terraform state list a terraform/ könyvtárban, a
# környezet workspace-ében fut.
# =============================================================================
set -uo pipefail

ENV="${1:-sbx}"
PROJECT="project-x"
BASE_ZONE="vighsandor.az.cubix-pe.hu"
ZONE="${PROJECT}.${ENV}.${BASE_ZONE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${ROOT}/segedscript/5-argocd-basics-5-homework.sh"
OUT="${ROOT}/kimenetek/segedscript-kimenet-${ENV}.md"
TF_DIR="${ROOT}/terraform"

for cmd in az kubectl kubelogin terraform; do
  command -v "$cmd" >/dev/null || { echo "Hiányzik: $cmd" >&2; exit 1; }
done
az account show -o none 2>/dev/null || { echo "Előbb: az login" >&2; exit 1; }
[[ -f "$HELPER" ]] || { echo "Nincs meg a segédscript: $HELPER" >&2; exit 1; }

echo "==> Csatlakozás a(z) ${PROJECT}-${ENV} clusterhez"
az aks get-credentials -g "${PROJECT}-${ENV}-aks" -n "${PROJECT}-${ENV}" --overwrite-existing >/dev/null
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes >/dev/null || { echo "A cluster nem érhető el." >&2; exit 1; }

echo "==> Terraform: init és workspace (${ENV}) a state listához"
terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" workspace select "$ENV" >/dev/null

# Ideiglenes másolat a környezet neveivel
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
sed -e "s|<domain>|${ZONE}|g" \
    -e "s|project-x-hw-externaldns|${PROJECT}-${ENV}-externaldns|g" \
    -e "s|project-x-sbx|${PROJECT}-${ENV}|g" \
    "$HELPER" > "$TMP"

mkdir -p "$(dirname "$OUT")"
{
  echo "# Erőforráslista – ${PROJECT} ${ENV} környezet (5. hét, Argo CD)"
  echo
  echo "A kurzus segédscriptje (\`segedscript/5-argocd-basics-5-homework.sh\`) alapján, a(z) \`${ENV}\` környezetre futtatva."
  echo "Készült: $(date '+%Y-%m-%d %H:%M %Z'), \`scripts/segedscript-futtatas.sh ${ENV}\`."
  echo
  echo "A futtatáshoz behelyettesített nevek: \`<domain>\` → \`${ZONE}\`; \`project-x-hw-externaldns\` → \`${PROJECT}-${ENV}-externaldns\`."
  echo "Minden parancs kimenete változtatás nélkül szerepel."
  echo
  echo "> Megjegyzés: a környezetemben a VNet saját (BYO), a \`${PROJECT}-${ENV}-aks\` resource groupban van, ezért a \`${PROJECT}-${ENV}-aks-nodes\` csoportra futó \`az network vnet list\` üres listát ad."
} > "$OUT"

pending_comment=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^#! ]] && continue
  if [[ -z "${line// }" ]]; then continue; fi
  if [[ "$line" =~ ^#[[:space:]]*(.*)$ ]]; then
    pending_comment="${BASH_REMATCH[1]}"
    continue
  fi
  echo "    $line"
  {
    echo
    if [[ -n "$pending_comment" ]]; then echo "## ${pending_comment}"; echo; pending_comment=""; fi
    echo '```console'
    echo "\$ ${line}"
    (cd "$TF_DIR" && bash -c "$line" 2>&1)
    echo '```'
  } >> "$OUT"
done < "$TMP"

echo
echo "==> Kész: ${OUT}"
