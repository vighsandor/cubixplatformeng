#!/usr/bin/env bash
# =============================================================================
# Project X miniplatform – környezet létrehozása (Terraform + kézi K8s-lépések)
#
# Használat:  ./kornyezet-letrehozas.sh <env>       (pl. sbx vagy dev)
#             AUTO_APPROVE=1 ./kornyezet-letrehozas.sh dev   (kérdés nélkül)
# Kényelmi indítók: ./sbx-letrehozas.sh, ./dev-letrehozas.sh
#
# 1. rész – Azure + Entra ID: Terraform (terraform/<env>)
# 2. rész – Kubernetesen belül: Helm/kubectl (ezen a héten szándékosan nem
#           Terraform), a Terraform-kimenetekből paraméterezve
# 3. rész – Ellenőrzés: segédscript, curl, state pillanatkép a repóba
# =============================================================================
ENV="${1:-${ENV:-}}"
[[ -n "$ENV" ]] || { echo "Használat: $0 <env>"; exit 1; }
source "$(dirname "$0")/kozos.sh"

# ---------------------------------------------------------------------------
# 1. rész – Infrastruktúra Terraformból
# ---------------------------------------------------------------------------
elofeltetelek
state_backend
tf_init
tf_apply

ZONE=$(tfo dns_zone_name)
APP_HOST="${APP}.${ZONE}"

# ---------------------------------------------------------------------------
# 2. rész – Kubernetesen belüli komponensek (kézi, Helm)
# ---------------------------------------------------------------------------
csatlakozas

log "Traefik ingress controller"
helm upgrade --install traefik traefik \
  --repo https://traefik.github.io/charts \
  --version 41.2.0 \
  --namespace ingress-controller \
  --create-namespace \
  --set service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set ports.web.http.redirections.entryPoint.to=websecure \
  --set ports.web.http.redirections.entryPoint.scheme=https \
  --set ports.web.http.redirections.entryPoint.permanent=true \
  --wait

EXTERNAL_IP=""
for i in $(seq 1 30); do
  EXTERNAL_IP=$(kubectl -n ingress-controller get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$EXTERNAL_IP" ]] && break
  sleep 10
done
[[ -n "$EXTERNAL_IP" ]] || { echo "Nem kapott EXTERNAL-IP-t a Traefik."; exit 1; }
echo "Traefik EXTERNAL-IP: $EXTERNAL_IP"

log "External DNS (values a Terraform-kimenetekből)"
VALUES="${K8S_DIR}/external-dns.${ENV}.values.yaml"
sed -e "s|__TXT_OWNER_ID__|$(tfo external_dns_txt_owner_id)|" \
    -e "s|__DNS_ZONE__|${ZONE}|" \
    -e "s|__CLIENT_ID__|$(tfo external_dns_client_id)|" \
    -e "s|__SUBSCRIPTION_ID__|$(tfo subscription_id)|" \
    -e "s|__IDENTITY_RG__|$(tfo aks_resource_group)|" \
    -e "s|__DNS_RG__|$(tfo dns_resource_group)|" \
    "${K8S_DIR}/external-dns.values.tmpl.yaml" > "$VALUES"
helm upgrade --install external-dns external-dns \
  --repo=https://kubernetes-sigs.github.io/external-dns/ \
  --version=1.20.0 \
  --namespace=external-dns --create-namespace \
  --values="$VALUES" \
  --wait

log "cert-manager és ClusterIssuer (letsencrypt, staging)"
helm upgrade --install cert-manager cert-manager \
  --version=v1.19.4 \
  --repo=https://charts.jetstack.io \
  --namespace=cert-manager --create-namespace \
  --set crds.enabled=true \
  --set prometheus.enabled=false \
  --wait
kubectl apply -f "${K8S_DIR}/cluster-issuer.yaml"

log "Demóalkalmazás (füstteszt): https://${APP_HOST}"
helm upgrade --install \
  --namespace="$APP" --create-namespace \
  "$APP" \
  oci://docker.io/ecklm/colors-demo-app \
  --set ingress.host="$APP_HOST" \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt

log "Várakozás a DNS-rekordra (External DNS, max. 5 perc)"
DNS_RG=$(tfo dns_resource_group)
for i in $(seq 1 30); do
  az network dns record-set a show -g "$DNS_RG" -z "$ZONE" -n "$APP" -o none 2>/dev/null && { echo "A rekord létrejött: $APP_HOST"; break; }
  sleep 10
  [[ $i -eq 30 ]] && warn "Nem jött létre az A rekord – nézd meg: kubectl -n external-dns logs deploy/external-dns"
done

log "Várakozás a tanúsítványra (max. 10 perc)"
kubectl -n "$APP" wait certificate --all --for=condition=Ready --timeout=600s \
  || warn "A tanúsítvány még nem READY – ellenőrizd: kubectl -n $APP get certificate,order"

# ---------------------------------------------------------------------------
# 3. rész – Ellenőrzés és a beadandó kimenetek
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
state_mentes

log "Segédscript futtatása (kimenetek/segedscript-kimenet-${ENV}.txt)"
# Az oktatói segédscript változatlan; csak a kitöltendő helyeit töltjük ki
# az adott környezet neveivel, és a Terraform-könyvtárban futtatjuk
# (a végén lévő `terraform state list` miatt).
RENDERED="$(mktemp)"
sed -e "s|<domain>|${ZONE}|g" \
    -e "s|project-x-hw-externaldns|${PROJEKT}-${ENV}-externaldns|g" \
    -e "s|project-x-sbx|${PROJEKT}-${ENV}|g" \
    "${REPO_ROOT}/segedscript/3-iac-7-homework.sh" > "$RENDERED"
(cd "$TF_DIR" && bash "$RENDERED") > "${OUT_DIR}/segedscript-kimenet-${ENV}.txt" 2>&1 || true
rm -f "$RENDERED"

log "Végpont ellenőrzése (kimenetek/curl-${ENV}.txt)"
{
  echo "\$ curl -sk https://${APP_HOST}"
  curl -sk "https://${APP_HOST}" || echo "(nincs válasz – DNS-gyorsítótár? Próbáld újra pár perc múlva.)"
} > "${OUT_DIR}/curl-${ENV}.txt"
grep -o '<title>.*</title>' "${OUT_DIR}/curl-${ENV}.txt" || warn "A válaszban nincs <title> – nézd meg a kimenetek/curl-${ENV}.txt fájlt."

log "Kész – ${PROJEKT}-${ENV}"
cat <<INFO
  Előfizetés:       $(tfo subscription_id)
  AKS:              $(tfo aks_resource_group) / $(tfo aks_name)
  DNS-zóna:         ${ZONE}
  Csoportok:        $(tfo platform_admins_group), $(tfo developers_group)
  Traefik IP:       ${EXTERNAL_IP}
  Demó:             https://${APP_HOST}   (staging tanúsítvány – a böngésző figyelmeztet)
  Beadandó fájlok:  terraform/${ENV}/state/, kimenetek/segedscript-kimenet-${ENV}.txt, kimenetek/curl-${ENV}.txt
INFO
