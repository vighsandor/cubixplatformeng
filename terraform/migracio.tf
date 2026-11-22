# -----------------------------------------------------------------------------
# Átállás a 4. heti Helm-telepítésekről az Argo CD-re
#
# Egy már futó környezetben a Terraform nem uninstallálja a korábbi
# helm_release-eket, csak "elengedi" őket (kiveszi a state-ből). Az Argo CD
# Application-ök ugyanazzal a release-névvel ugyanazokat az erőforrásokat
# írják le, így átveszik őket: nincs leállás, nem törlődik a DNS-rekord vagy a
# tanúsítvány. Új környezetben ezek a blokkok nem csinálnak semmit.
# (Terraform >= 1.7)
# -----------------------------------------------------------------------------

removed {
  from = helm_release.traefik
  lifecycle { destroy = false }
}

removed {
  from = helm_release.external_dns
  lifecycle { destroy = false }
}

removed {
  from = helm_release.cert_manager
  lifecycle { destroy = false }
}

removed {
  from = helm_release.cluster_issuer
  lifecycle { destroy = false }
}

removed {
  from = helm_release.demo_app
  lifecycle { destroy = false }
}
