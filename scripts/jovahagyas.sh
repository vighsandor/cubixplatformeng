#!/usr/bin/env bash
# =============================================================================
# A sandbox utáni környezetek apply-jának jóváhagyása (GitHub environment:
# promotion) a fő ág legutóbbi Terraform-futásában.
#
#   ./scripts/jovahagyas.sh            # a legutóbbi futás
#   ./scripts/jovahagyas.sh <run-id>   # egy megadott futás
#
# Ugyanez a felületen: Actions -> a futás -> Review deployments -> Approve.
# Csak akkor hagyd jóvá, ha a sandbox apply-ja sikeres volt, és a sandboxban
# minden rendben van (Argo CD: Synced/Healthy, a demóalkalmazás válaszol).
# =============================================================================
set -euo pipefail

REPO="${GH_REPO_FULL:-vighsandor/cubixplatformeng}"
BRANCH="${GH_BRANCH:-platformeng-w3}"

command -v gh >/dev/null || { echo "Hiányzik: gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Előbb: gh auth login" >&2; exit 1; }

run_id="${1:-$(gh run list -R "$REPO" --workflow terraform.yml --branch "$BRANCH" --event push \
                 --limit 1 --json databaseId -q '.[0].databaseId')}"
[[ -n "$run_id" ]] || { echo "Nincs Terraform-futás a(z) $BRANCH ágon." >&2; exit 1; }
echo "Futás: https://github.com/${REPO}/actions/runs/${run_id}"
echo

echo "A jobok állapota:"
gh run view "$run_id" -R "$REPO" --json jobs \
  -q '.jobs[] | "  \(.name): \(.status)\(if .conclusion != "" then " / " + .conclusion else "" end)"'
echo

pending="$(gh api "repos/${REPO}/actions/runs/${run_id}/pending_deployments")"
if [[ "$(jq length <<<"$pending")" == "0" ]]; then
  echo "Ebben a futásban nincs jóváhagyásra váró telepítés."
  exit 0
fi
jq -r '.[] | "Jóváhagyásra vár: \(.environment.name) (jóváhagyhatod: \(.current_user_can_approve))"' <<<"$pending"

read -r -p "Jóváhagyod a továbbvitelt? Írd be: igen > " answer
[[ "$answer" == "igen" ]] || { echo "Nem hagytam jóvá."; exit 1; }

args=()
while read -r id; do args+=(-F "environment_ids[]=${id}"); done < <(jq -r '.[].environment.id' <<<"$pending")
gh api -X POST "repos/${REPO}/actions/runs/${run_id}/pending_deployments" \
  "${args[@]}" -f state=approved -f comment="A sandbox rendben, továbbvitel jóváhagyva." >/dev/null
echo "Jóváhagyva. Követés: gh run watch ${run_id} -R ${REPO}"
