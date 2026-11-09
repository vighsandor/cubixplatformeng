#!/usr/bin/env bash
# =============================================================================
# Project X miniplatform – környezet lebontása
#
# Használat:  ./kornyezet-lebontas.sh <env>       (pl. sbx vagy dev)
#             AUTO_APPROVE=1 ./kornyezet-lebontas.sh dev   (kérdés nélkül)
# Kényelmi indítók: ./sbx-lebontas.sh, ./dev-lebontas.sh
#
# A repóba mentett state-pillanatképhez (terraform/<env>/state/) nem nyúl,
# az a létrehozás utáni állapotot dokumentálja.
# =============================================================================
ENV="${1:-${ENV:-}}"
[[ -n "$ENV" ]] || { echo "Használat: $0 <env>"; exit 1; }
source "$(dirname "$0")/kozos.sh"

elofeltetelek
tf_init

if [[ "${AUTO_APPROVE:-0}" != "1" ]]; then
  read -r -p "Biztosan lebontod a ${PROJEKT}-${ENV} környezetet? Írd be a nevét (${PROJEKT}-${ENV}): " valasz
  [[ "$valasz" == "${PROJEKT}-${ENV}" ]] || { echo "Megszakítva."; exit 1; }
fi

# 1. Kubernetesen belüli komponensek (best effort): előbb az alkalmazás, hogy
#    az External DNS a saját rekordjait még kitörölje, utána a többi.
if AKS_RG=$(tfo aks_resource_group 2>/dev/null) && AKS_NAME=$(tfo aks_name 2>/dev/null); then
  log "Kubernetesen belüli komponensek eltávolítása"
  if az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing 2>/dev/null \
     && kubelogin convert-kubeconfig -l azurecli \
     && kubectl get nodes >/dev/null 2>&1; then
    helm -n "$APP" uninstall "$APP" 2>/dev/null || true
    echo "Várakozás, hogy az External DNS törölje a rekordokat (30 s)..."
    sleep 30
    helm -n external-dns uninstall external-dns 2>/dev/null || true
    helm -n cert-manager uninstall cert-manager 2>/dev/null || true
    # A Traefik törlése felszabadítja a load balancer publikus IP-jét
    helm -n ingress-controller uninstall traefik --wait 2>/dev/null || true
  else
    warn "A cluster nem érhető el – a Kubernetes-lépéseket kihagyom."
  fi
fi

# 2. Azure + Entra ID: minden, amit a Terraform létrehozott
log "terraform destroy"
tf destroy -input=false -auto-approve

# 3. Helyi takarítás
kubectl config delete-context "${PROJEKT}-${ENV}" 2>/dev/null || true
kubectl config delete-cluster "${PROJEKT}-${ENV}" 2>/dev/null || true
rm -f "${K8S_DIR}/external-dns.${ENV}.values.yaml"

log "Kész – a ${PROJEKT}-${ENV} környezet lebontva"
echo "A Terraform state (üres) a ${STATE_SA}/${STATE_CONTAINER} tárolóban marad; a repóban lévő pillanatkép változatlan."
