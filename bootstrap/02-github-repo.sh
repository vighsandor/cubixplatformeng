#!/usr/bin/env bash
# =============================================================================
# 2. lépés (egyszer): a GitHub repo beállítása a gh CLI-vel
#
#   ./02-github-repo.sh secrets          – az Azure-bejelentkezés secretjei
#   ./02-github-repo.sh default-branch   – a fő ág legyen az alapértelmezett
#   ./02-github-repo.sh environments     – "promotion" environment: a sandbox
#                                          utáni környezetek apply-ja csak
#                                          jóváhagyással, csak a fő ágról
#   ./02-github-repo.sh ruleset          – ágvédelem a fő ágon (az első sikeres
#                                          pipeline-futás után kapcsold be!)
#   ./02-github-repo.sh all              – mind
#
# Előfeltétel: gh auth login (a repo adminjaként), az login.
# =============================================================================
set -euo pipefail

REPO="${GH_REPO_FULL:-vighsandor/cubixplatformeng}"
BRANCH="${GH_BRANCH:-platformeng-w3}"
RG="course-baseline"
IDENTITY="github-repos"
RULESET_NAME="${BRANCH} – pull request + terraform plan"
CHECK_NAME="Terraform Plan" # a terraform.yml plan-result jobjának neve
GH_ENVIRONMENT="${GH_ENVIRONMENT:-promotion}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
command -v gh >/dev/null || { echo "Hiányzik: gh (GitHub CLI) – https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Előbb: gh auth login"; exit 1; }

secrets() {
  log "Repo secretek (${REPO})"
  az account show -o none 2>/dev/null || { echo "Előbb: az login"; exit 1; }
  gh secret set AZURE_CLIENT_ID       -R "$REPO" -b "$(az identity show -g "$RG" -n "$IDENTITY" --query clientId -o tsv)"
  gh secret set AZURE_TENANT_ID       -R "$REPO" -b "$(az account show --query tenantId -o tsv)"
  gh secret set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$(az account show --query id -o tsv)"
  gh secret list -R "$REPO"
}

default_branch() {
  log "Alapértelmezett ág: ${BRANCH}"
  echo "A workflow_dispatch (pl. a Terraform destroy kézi indítása) csak az alapértelmezett ágon"
  echo "lévő workflow-kra működik, és a pull requestek is ezt kínálják fel célágnak."
  gh repo edit "$REPO" --default-branch "$BRANCH"
}

environments() {
  log "GitHub environment: ${GH_ENVIRONMENT} (jóváhagyás a sandbox utáni környezetekhez)"
  local me body
  me=$(gh api user --jq .id)
  body=$(jq -n --argjson me "$me" '{
    wait_timer: 0,
    prevent_self_review: false,
    reviewers: [ { type: "User", id: $me } ],
    deployment_branch_policy: { protected_branches: false, custom_branch_policies: true } }')
  if ! gh api -X PUT "repos/${REPO}/environments/${GH_ENVIRONMENT}" --input - <<<"$body" >/dev/null; then
    echo "  FIGYELEM: a kötelező jóváhagyó beállítása nem sikerült. Privát repónál ez a"
    echo "  GitHub ingyenes csomagjában nem érhető el; ilyenkor az environment jóváhagyó"
    echo "  nélkül jön létre (a sandbox utáni sorrend ettől még megmarad)."
    gh api -X PUT "repos/${REPO}/environments/${GH_ENVIRONMENT}" \
      -F 'deployment_branch_policy[protected_branches]=false' \
      -F 'deployment_branch_policy[custom_branch_policies]=true' >/dev/null
  fi
  # Csak a fő ágról lehet ebbe az environmentbe telepíteni
  if ! gh api "repos/${REPO}/environments/${GH_ENVIRONMENT}/deployment-branch-policies" \
      --jq '.branch_policies[].name' | grep -qx "$BRANCH"; then
    gh api -X POST "repos/${REPO}/environments/${GH_ENVIRONMENT}/deployment-branch-policies" \
      -f name="$BRANCH" -f type=branch >/dev/null
  fi
  gh api "repos/${REPO}/environments/${GH_ENVIRONMENT}" \
    --jq '"  jóváhagyók: \([.protection_rules[]? | select(.type=="required_reviewers") | .reviewers[].reviewer.login] | join(", ") | if . == "" then "nincs" else . end); ág: '"$BRANCH"'"'
}

ruleset() {
  log "Ruleset: ${RULESET_NAME}"
  local body id
  body=$(jq -n --arg name "$RULESET_NAME" --arg ref "refs/heads/${BRANCH}" --arg check "$CHECK_NAME" '{
    name: $name,
    target: "branch",
    enforcement: "active",
    bypass_actors: [],
    conditions: { ref_name: { include: [$ref], exclude: [] } },
    rules: [
      { type: "deletion" },
      { type: "non_fast_forward" },
      { type: "pull_request", parameters: {
          required_approving_review_count: 0,
          dismiss_stale_reviews_on_push: false,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_review_thread_resolution: false } },
      { type: "required_status_checks", parameters: {
          strict_required_status_checks_policy: true,
          do_not_enforce_on_create: false,
          required_status_checks: [ { context: $check, integration_id: 15368 } ] } }
    ] }')
  id=$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id")
  if [[ -n "$id" ]]; then
    gh api -X PUT "repos/${REPO}/rulesets/${id}" --input - <<<"$body" >/dev/null
    echo "  frissítve (id: $id)"
  else
    gh api -X POST "repos/${REPO}/rulesets" --input - <<<"$body" --jq '"  létrehozva (id: \(.id))"'
  fi
  cat <<INFO
  Szabályok a(z) ${BRANCH} ágon:
    - csak pull requesten keresztül kerülhet bele kód (közvetlen push tiltva)
    - kötelező ellenőrzés: "${CHECK_NAME}" (fmt + validate + plan minden környezetre)
    - az ágnak naprakésznek kell lennie a fő ághoz képest (semi-linear history)
    - force push és az ág törlése tiltva
INFO
}

case "${1:-}" in
  secrets) secrets ;;
  default-branch) default_branch ;;
  environments) environments ;;
  ruleset) ruleset ;;
  all) secrets; default_branch; environments; ruleset ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
