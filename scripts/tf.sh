#!/usr/bin/env bash
# =============================================================================
# Terraform helyi futtatása egy környezetre (hibakereséshez, vészhelyzetre).
# A rendes út a pull request + pipeline; helyben csak plan-t futtass, kivéve,
# ha a pipeline nem elérhető.
#
#   ./scripts/tf.sh <env> plan|apply|destroy|output
# =============================================================================
set -euo pipefail
ENV="${1:?Használat: $0 <env> plan|apply|destroy|output}"
ACTION="${2:?Használat: $0 <env> plan|apply|destroy|output}"
TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
VARS="environments/${ENV}.tfvars"

for cmd in az terraform kubelogin; do command -v "$cmd" >/dev/null || { echo "Hiányzik: $cmd"; exit 1; }; done
az account show -o none 2>/dev/null || { echo "Előbb: az login"; exit 1; }
[[ -f "${TF_DIR}/${VARS}" ]] || { echo "Nincs ilyen környezet: ${VARS}"; exit 1; }

tf() { terraform -chdir="$TF_DIR" "$@"; }
tf init -input=false >/dev/null
tf workspace select -or-create "$ENV"
case "$ACTION" in
  plan)    tf plan -lock-timeout=10m -var-file="$VARS" ;;
  apply)   tf plan -lock-timeout=10m -var-file="$VARS" -out=tfplan && \
           read -r -p "Alkalmazzam? (igen/nem) " v && [[ "$v" == igen ]] && tf apply tfplan; rm -f "${TF_DIR}/tfplan" ;;
  destroy) read -r -p "A(z) ${ENV} környezet TELJES lebontása. Írd be a nevét: " v
           [[ "$v" == "$ENV" ]] && tf destroy -lock-timeout=10m -var-file="$VARS" ;;
  output)  tf output ;;
  *) echo "Ismeretlen művelet: $ACTION"; exit 1 ;;
esac
