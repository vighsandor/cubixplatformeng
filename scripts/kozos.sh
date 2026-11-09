#!/usr/bin/env bash
# =============================================================================
# Project X miniplatform – közös függvények a létrehozó és lebontó scriptekhez
# Nem önállóan futtatandó: a <env>-letrehozas.sh / <env>-lebontas.sh tölti be.
# =============================================================================
set -euo pipefail

PROJEKT="${PROJEKT:-project-x}"
: "${ENV:?Az ENV változó kötelező (sbx vagy dev)}"
APP="${APP:-colors}"

SUBSCRIPTION_ID="a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449"

# Terraform state backend (course-baseline – ezt a Terraform-kód nem kezeli)
STATE_RG="course-baseline"
STATE_SA="${STATE_SA:-platencbvighsandor}"
STATE_SA_LOCATION="${STATE_SA_LOCATION:-swedencentral}"
STATE_CONTAINER="tfstate"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/${ENV}"
K8S_DIR="${REPO_ROOT}/k8s"
OUT_DIR="${REPO_ROOT}/kimenetek"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mFIGYELEM: %s\033[0m\n' "$*"; }
tf()   { terraform -chdir="$TF_DIR" "$@"; }
tfo()  { tf output -raw "$1"; }

elofeltetelek() {
  log "Előfeltételek ellenőrzése"
  local cmd
  for cmd in az terraform kubectl kubelogin helm curl; do
    command -v "$cmd" >/dev/null || { echo "Hiányzik: $cmd"; exit 1; }
  done
  [[ -d "$TF_DIR" ]] || { echo "Nincs ilyen Terraform-könyvtár: $TF_DIR"; exit 1; }
  az account show -o none 2>/dev/null || { echo "Előbb jelentkezz be: az login"; exit 1; }
  az account set --subscription "$SUBSCRIPTION_ID"
  az account show --query "{Subscription:name, User:user.name}" -o table

  # Egy friss előfizetésben az erőforrás-szolgáltatók (resource providerek)
  # nincsenek regisztrálva; ilyenkor pl. a storage account létrehozása
  # félrevezető "SubscriptionNotFound" hibát ad. Regisztrálás, ha kell.
  log "Erőforrás-szolgáltatók regisztrációja"
  local ns state
  for ns in Microsoft.Storage Microsoft.ContainerService Microsoft.Network Microsoft.ManagedIdentity Microsoft.Compute; do
    state=$(az provider show -n "$ns" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)
    if [[ "$state" != "Registered" ]]; then
      echo "  $ns: $state -> regisztrálás (1-3 perc)..."
      az provider register -n "$ns" --wait -o none
    fi
    echo "  $ns: Registered"
  done
}

# A state tárolója a kurzus elején, kézzel készült (course-baseline).
# Ha valamiért hiányzik, itt pótoljuk; ha megvan, nem nyúlunk hozzá.
state_backend() {
  log "Terraform state backend: ${STATE_SA}/${STATE_CONTAINER}"
  if ! az storage account show -g "$STATE_RG" -n "$STATE_SA" -o none 2>/dev/null; then
    az storage account create -g "$STATE_RG" -n "$STATE_SA" -l "$STATE_SA_LOCATION" \
      --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false -o none
  fi
  local sa_id me
  sa_id=$(az storage account show -g "$STATE_RG" -n "$STATE_SA" --query id -o tsv)
  me=$(az ad signed-in-user show --query id -o tsv)
  if [[ -z "$(az role assignment list --assignee "$me" --scope "$sa_id" --role "Storage Blob Data Contributor" --query '[].id' -o tsv)" ]]; then
    az role assignment create --assignee-object-id "$me" --assignee-principal-type User \
      --role "Storage Blob Data Contributor" --scope "$sa_id" -o none
    echo "Várakozás a szerepkör életbe lépésére (60 s)..."
    sleep 60
  fi
  if [[ "$(az storage container exists -n "$STATE_CONTAINER" --account-name "$STATE_SA" --auth-mode login --query exists -o tsv)" != "true" ]]; then
    az storage container create -n "$STATE_CONTAINER" --account-name "$STATE_SA" --auth-mode login -o none
  fi
}

tf_init() {
  log "terraform init (${TF_DIR})"
  tf init -input=false
}

# Plan, megerősítés, apply. AUTO_APPROVE=1 esetén nem kérdez.
tf_apply() {
  log "terraform plan"
  tf plan -input=false -out=tfplan
  if [[ "${AUTO_APPROVE:-0}" != "1" ]]; then
    read -r -p "Alkalmazzam a fenti tervet? (igen/nem) " valasz
    [[ "$valasz" == "igen" ]] || { echo "Megszakítva."; rm -f "$TF_DIR/tfplan"; exit 1; }
  fi
  log "terraform apply"
  tf apply -input=false tfplan
  rm -f "$TF_DIR/tfplan"
}

# A state pillanatképe a repóba (a beadandóhoz): terraform/<env>/state/
state_mentes() {
  local cel="$TF_DIR/state/${PROJEKT}-${ENV}.tfstate"
  log "State pillanatkép mentése: ${cel#$REPO_ROOT/}"
  mkdir -p "$TF_DIR/state"
  tf state pull > "$cel"
  tf state list > "$TF_DIR/state/${PROJEKT}-${ENV}.state-list.txt"
}

csatlakozas() {
  log "Csatlakozás a clusterhez"
  az aks get-credentials -g "$(tfo aks_resource_group)" -n "$(tfo aks_name)" --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli
  echo "Várakozás, amíg a csoporton keresztüli RBAC-jogosultság érvénybe lép (max. 10 perc)..."
  local i
  for i in $(seq 1 60); do
    kubectl get nodes 2>/dev/null && return 0
    sleep 10
  done
  echo "A kubectl 10 perc alatt sem kapott hozzáférést. Próbáld: az logout && az login, majd futtasd újra."
  exit 1
}

