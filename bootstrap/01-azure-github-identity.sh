#!/usr/bin/env bash
# =============================================================================
# 1. lépés (egyszer): a GitHub Actions Azure-identitása
#
# Létrehozza / ellenőrzi (újrafuttatható):
#   - a github-repos managed identityt a course-baseline resource groupban
#   - a federated credentialöket (a fő ágra és a pull requestekre) – titok nélkül
#   - Azure-jogok: Owner az előfizetésen, Storage Blob Data Contributor a state-en
#   - Entra ID-szerepkörök: Groups Administrator (csoportok kezelése),
#     Directory Readers (felhasználók kikeresése UPN alapján)
#
# Futtatás: saját felhasználóval, `az login` után (Owner + Entra-adminjog kell).
# =============================================================================
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449}"
RG="course-baseline"
LOCATION="swedencentral"
IDENTITY="github-repos"
STATE_SA="platencbvighsandor"
GH_OWNER="${GH_OWNER:-vighsandor}"
GH_REPO="${GH_REPO:-cubixplatformeng}"
GH_BRANCH="${GH_BRANCH:-platformeng-w3}"

GITHUB_ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"
ROLE_GROUPS_ADMIN="fdd7a751-b60b-444a-984c-02652fe8fa1c"     # Groups Administrator
ROLE_DIRECTORY_READERS="88d8e3e3-8f55-4a1e-953a-9b9898b8876b" # Directory Readers

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
retry() { local i; for i in 1 2 3 4 5 6; do "$@" && return 0; echo "  újrapróbálás ${i}/6 (20 s)..."; sleep 20; done; return 1; }

for cmd in az curl jq; do command -v "$cmd" >/dev/null || { echo "Hiányzik: $cmd"; exit 1; }; done
az account show -o none 2>/dev/null || { echo "Előbb: az login"; exit 1; }
az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID=$(az account show --query tenantId -o tsv)

log "Managed identity: ${RG}/${IDENTITY}"
az identity show -g "$RG" -n "$IDENTITY" -o none 2>/dev/null \
  || az identity create -g "$RG" -n "$IDENTITY" -l "$LOCATION" -o none
CLIENT_ID=$(az identity show -g "$RG" -n "$IDENTITY" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -g "$RG" -n "$IDENTITY" --query principalId -o tsv)
echo "  clientId:    $CLIENT_ID"
echo "  principalId: $PRINCIPAL_ID"

log "GitHub-azonosítók: ${GH_OWNER}/${GH_REPO}"
GH_JSON=$(curl -fsSL "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}")
OWNER_ID=$(jq -r .owner.id <<<"$GH_JSON")
REPO_ID=$(jq -r .id <<<"$GH_JSON")
echo "  owner id: $OWNER_ID, repo id: $REPO_ID"

# A GitHub az OIDC-token "sub" mezőjében új repóknál már a módosíthatatlan
# azonosítókat is küldi (repo:owner@id/repo@id:...), régebbieknél a régi formát.
# Mindkettőt felveszem, így bármelyiket küldi, a bejelentkezés működik.
NEW_PREFIX="repo:${GH_OWNER}@${OWNER_ID}/${GH_REPO}@${REPO_ID}"
OLD_PREFIX="repo:${GH_OWNER}/${GH_REPO}"
declare -A CREDS=(
  ["branch-${GH_BRANCH}"]="${NEW_PREFIX}:ref:refs/heads/${GH_BRANCH}"
  ["pull-request"]="${NEW_PREFIX}:pull_request"
  ["branch-${GH_BRANCH}-legacy"]="${OLD_PREFIX}:ref:refs/heads/${GH_BRANCH}"
  ["pull-request-legacy"]="${OLD_PREFIX}:pull_request"
)
log "Federated credentials"
for name in "${!CREDS[@]}"; do
  if az identity federated-credential show -g "$RG" --identity-name "$IDENTITY" -n "$name" -o none 2>/dev/null; then
    echo "  megvan: $name"
  else
    az identity federated-credential create -g "$RG" --identity-name "$IDENTITY" -n "$name" \
      --issuer "$GITHUB_ISSUER" --subject "${CREDS[$name]}" --audiences "$AUDIENCE" -o none
    echo "  + $name -> ${CREDS[$name]}"
  fi
done

assign() { # $1=szerepkör $2=scope
  if [[ -n "$(az role assignment list --assignee "$PRINCIPAL_ID" --role "$1" --scope "$2" --query '[].id' -o tsv)" ]]; then
    echo "  megvan: $1"
  else
    retry az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
      --role "$1" --scope "$2" -o none
    echo "  + $1"
  fi
}
log "Azure-jogok"
assign "Owner" "/subscriptions/${SUBSCRIPTION_ID}"
SA_ID=$(az storage account show -g "$RG" -n "$STATE_SA" --query id -o tsv)
assign "Storage Blob Data Contributor" "$SA_ID"

directory_role() { # $1=role template id $2=név
  local existing
  existing=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?\$filter=principalId eq '${PRINCIPAL_ID}' and roleDefinitionId eq '$1'" \
    --query "length(value)" -o tsv)
  if [[ "$existing" != "0" ]]; then
    echo "  megvan: $2"
  else
    retry az rest --method POST --url "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments" \
      --headers "Content-Type=application/json" \
      --body "{\"principalId\":\"${PRINCIPAL_ID}\",\"roleDefinitionId\":\"$1\",\"directoryScopeId\":\"/\"}" -o none
    echo "  + $2"
  fi
}
log "Entra ID-szerepkörök"
directory_role "$ROLE_GROUPS_ADMIN" "Groups Administrator"
directory_role "$ROLE_DIRECTORY_READERS" "Directory Readers"

log "Kész. A GitHub repo secretjei (a 02-github-repo.sh beállítja őket):"
cat <<INFO
  AZURE_CLIENT_ID       = ${CLIENT_ID}
  AZURE_TENANT_ID       = ${TENANT_ID}
  AZURE_SUBSCRIPTION_ID = ${SUBSCRIPTION_ID}
INFO
