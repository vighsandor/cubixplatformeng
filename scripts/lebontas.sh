#!/usr/bin/env bash
# =============================================================================
# Környezetek lebontása a pipeline-nal (Terraform destroy workflow)
#
# Használat:   ./scripts/lebontas.sh                # dev, majd sbx
#              ./scripts/lebontas.sh dev            # csak a megadott(ak)
#
# Környezetenként elindítja a "Terraform destroy" workflow-t a fő ágon
# (environment = confirm = <env>), megvárja a végét, hiba esetén kiírja a
# napló végét és megáll. A végén az Azure-ban és az Entra ID-ban ellenőrzi,
# hogy nem maradt-e semmi (ha az "az" CLI be van jelentkezve).
#
# Szükséges: gh (bejelentkezve), jq; az ellenőrzéshez: az.
# FONTOS: a környezetek tfvars fájljai a fő ágon maradnak, ezért a fő ágra
# kerülő következő merge (vagy kézi Terraform-futás) újra felépíti őket.
# =============================================================================
set -euo pipefail

REPO="${GH_REPO:-vighsandor/cubixplatformeng}"
BRANCH="${GH_BRANCH:-platformeng-w3}"
WORKFLOW="terraform-destroy.yml"
PROJECT="project-x"
PARENT_ZONE="vighsandor.az.cubix-pe.hu"
PARENT_RG="course-baseline"

if [[ $# -gt 0 ]]; then ENVS=("$@"); else ENVS=(dev sbx); fi

for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "HIBA: hiányzik: $cmd" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "HIBA: előbb: gh auth login" >&2; exit 1; }

echo "Repó: $REPO, ág: $BRANCH, lebontandó környezetek: ${ENVS[*]}"
read -r -p "Biztosan lebontod őket? Írd be: igen > " answer
[[ "$answer" == "igen" ]] || { echo "Megszakítva."; exit 1; }

for env in "${ENVS[@]}"; do
  echo
  echo "==> $env: Terraform destroy indítása"
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gh workflow run "$WORKFLOW" -R "$REPO" --ref "$BRANCH" \
    -f environment="$env" -f confirm="$env"

  # A most indított futás azonosítója (az indítás után létrejött első futás)
  run_id=""
  for _ in $(seq 1 30); do
    sleep 5
    run_id="$(gh run list -R "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch \
                --limit 10 --json databaseId,createdAt \
              | jq -r --arg s "$start" '[.[] | select(.createdAt >= $s)] | sort_by(.createdAt) | .[0].databaseId // empty')"
    [[ -n "$run_id" ]] && break
  done
  [[ -n "$run_id" ]] || { echo "HIBA: nem találom az elindított futást." >&2; exit 1; }
  echo "    futás: https://github.com/$REPO/actions/runs/$run_id"

  if gh run watch "$run_id" -R "$REPO" --exit-status --interval 30 >/dev/null; then
    echo "    $env: a lebontás sikeres."
    gh run view "$run_id" -R "$REPO" --log | grep -E "Destroy complete!" | sed 's/^.*Z /    /' || true
  else
    echo "HIBA: a(z) $env lebontása nem sikerült. A napló vége:" >&2
    gh run view "$run_id" -R "$REPO" --log-failed | tail -40 | cut -f3- >&2
    exit 1
  fi
done

echo
echo "==> Ellenőrzés: maradt-e valami"
if command -v az >/dev/null && az account show >/dev/null 2>&1; then
  left=0
  for env in "${ENVS[@]}"; do
    rgs="$(az group list --query "[?starts_with(name,'${PROJECT}-${env}-')].name" -o tsv)"
    ns="$(az network dns record-set ns list -g "$PARENT_RG" -z "$PARENT_ZONE" \
            --query "[?name=='${PROJECT}.${env}'].name" -o tsv)"
    grps="$(az ad group list --filter "startswith(displayName,'${PROJECT}-${env}-')" --query "[].displayName" -o tsv)"
    for item in $rgs $ns $grps; do echo "    MARADT ($env): $item"; left=1; done
  done
  # Az AKS node resource group törlése néhány percig a háttérben még tarthat
  [[ $left -eq 0 ]] && echo "    Semmi nem maradt." \
                    || echo "    A node resource group (…-aks-nodes) törlése néhány percig még tarthat; ha később is megvan, nézd meg kézzel."
else
  echo "    (Az 'az' CLI nincs bejelentkezve, az ellenőrzést kihagyom: az login)"
fi

echo
echo "Kész. Figyelem: a tfvars fájlok a fő ágon maradtak, ezért a fő ágra kerülő"
echo "következő merge újra felépíti a környezeteket. A nyitott PR-t ne merge-öld,"
echo "ha nem akarod, hogy a dev újra létrejöjjön."
