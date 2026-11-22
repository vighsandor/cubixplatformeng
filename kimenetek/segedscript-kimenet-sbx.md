# Erőforráslista – project-x sbx környezet (5. hét, Argo CD)

A kurzus segédscriptje (`segedscript/5-argocd-basics-5-homework.sh`) alapján, a(z) `sbx` környezetre futtatva.
Készült: 2026-11-22 19:28 CET, `scripts/segedscript-futtatas.sh sbx`.

A futtatáshoz behelyettesített nevek: `<domain>` → `project-x.sbx.vighsandor.az.cubix-pe.hu`; `project-x-hw-externaldns` → `project-x-sbx-externaldns`.
Minden parancs kimenete változtatás nélkül szerepel.

> Megjegyzés: a környezetemben a VNet saját (BYO), a `project-x-sbx-aks` resource groupban van, ezért a `project-x-sbx-aks-nodes` csoportra futó `az network vnet list` üres listát ad.

```console
$ az group list -o table
Name                     Location       Status
-----------------------  -------------  ---------
azure-signup-rg          eastus         Succeeded
course-baseline          swedencentral  Succeeded
NetworkWatcherRG         swedencentral  Succeeded
project-x-sbx-dns        swedencentral  Succeeded
project-x-sbx-aks        swedencentral  Succeeded
project-x-sbx-aks-nodes  swedencentral  Succeeded
project-x-dev-aks        swedencentral  Succeeded
project-x-dev-dns        swedencentral  Succeeded
project-x-dev-aks-nodes  swedencentral  Succeeded
```

```console
$ az aks list -o table
Name           Location       ResourceGroup      KubernetesVersion    CurrentKubernetesVersion    ProvisioningState    Fqdn
-------------  -------------  -----------------  -------------------  --------------------------  -------------------  ------------------------------------------------------
project-x-sbx  swedencentral  project-x-sbx-aks  1.36.3               1.36.3                      Succeeded            project-x-sbx-dns-pjonmqc4.hcp.swedencentral.azmk8s.io
project-x-dev  swedencentral  project-x-dev-aks  1.36.3               1.36.3                      Succeeded            project-x-dev-dns-9ovzz2ht.hcp.swedencentral.azmk8s.io
```

```console
$ az network vnet list --resource-group project-x-sbx-aks-nodes -o table

```

```console
$ az network dns zone list
[
  {
    "etag": "77f79121-66ee-4cf4-ad20-4d9909197616",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Network/dnszones/vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-05.azure-dns.com.",
      "ns2-05.azure-dns.net.",
      "ns3-05.azure-dns.org.",
      "ns4-05.azure-dns.info."
    ],
    "numberOfRecordSets": 4,
    "resourceGroup": "course-baseline",
    "tags": {},
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  },
  {
    "etag": "892bb7fa-8851-4b75-9efe-0e85debab2f4",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-dns/providers/Microsoft.Network/dnszones/project-x.dev.vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "project-x.dev.vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-08.azure-dns.com.",
      "ns2-08.azure-dns.net.",
      "ns3-08.azure-dns.org.",
      "ns4-08.azure-dns.info."
    ],
    "numberOfRecordSets": 6,
    "resourceGroup": "project-x-dev-dns",
    "tags": {
      "environment": "dev",
      "expires": "2027-02-21",
      "managed_by": "terraform",
      "owner": "platformengineer@vighsandor.hu",
      "project": "project-x",
      "team": "Project X"
    },
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  },
  {
    "etag": "0ac3cc3d-ce61-45f8-94ed-bfaebab713fe",
    "id": "/subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnszones/project-x.sbx.vighsandor.az.cubix-pe.hu",
    "location": "global",
    "maxNumberOfRecordSets": 10000,
    "name": "project-x.sbx.vighsandor.az.cubix-pe.hu",
    "nameServers": [
      "ns1-09.azure-dns.com.",
      "ns2-09.azure-dns.net.",
      "ns3-09.azure-dns.org.",
      "ns4-09.azure-dns.info."
    ],
    "numberOfRecordSets": 6,
    "resourceGroup": "project-x-sbx-dns",
    "tags": {
      "environment": "sbx",
      "expires": "2027-02-21",
      "managed_by": "terraform",
      "owner": "platformengineer@vighsandor.hu",
      "project": "project-x",
      "team": "Project X"
    },
    "type": "Microsoft.Network/dnszones",
    "zoneType": "Public"
  }
]
```

## A bejegyzett DNS nevek listája

```console
$ az network dns record-set list --resource-group project-x-sbx-dns --zone-name project-x.sbx.vighsandor.az.cubix-pe.hu -o table
TTL     Fqdn                                               Name      ProvisioningState    ResourceGroup
------  -------------------------------------------------  --------  -------------------  -----------------
172800  project-x.sbx.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-sbx-dns
3600    project-x.sbx.vighsandor.az.cubix-pe.hu.           @         Succeeded            project-x-sbx-dns
300     a-argocd.project-x.sbx.vighsandor.az.cubix-pe.hu.  a-argocd  Succeeded            project-x-sbx-dns
300     a-colors.project-x.sbx.vighsandor.az.cubix-pe.hu.  a-colors  Succeeded            project-x-sbx-dns
300     argocd.project-x.sbx.vighsandor.az.cubix-pe.hu.    argocd    Succeeded            project-x-sbx-dns
300     colors.project-x.sbx.vighsandor.az.cubix-pe.hu.    colors    Succeeded            project-x-sbx-dns
```

## Kubernetesen belüli erőforrások listája és státusza

```console
$ kubectl get -A pods,ingress,ClusterIssuer,secrets,namespace,apps,appprojects,appsets
NAMESPACE            NAME                                                       READY   STATUS    RESTARTS   AGE
argocd               pod/argocd-application-controller-0                        1/1     Running   0          87m
argocd               pod/argocd-applicationset-controller-5f4cc5f454-k2v5s      1/1     Running   0          87m
argocd               pod/argocd-notifications-controller-55486f974b-lnh4d       1/1     Running   0          87m
argocd               pod/argocd-redis-84885db6b7-6hg2d                          1/1     Running   0          87m
argocd               pod/argocd-repo-server-5b594d447-9xb9q                     1/1     Running   0          87m
argocd               pod/argocd-server-5589dc795b-wld9h                         1/1     Running   0          87m
cert-manager         pod/cert-manager-687c8dcfbb-nk2rz                          1/1     Running   0          86m
cert-manager         pod/cert-manager-cainjector-5bfdf76ddd-rmgh8               1/1     Running   0          86m
cert-manager         pod/cert-manager-webhook-578b8cbb44-dkl8k                  1/1     Running   0          86m
colors               pod/colors-colors-demo-app-5ffff85675-xdmkt                1/1     Running   0          86m
external-dns         pod/external-dns-5cd545c95d-rglv2                          1/1     Running   0          86m
ingress-controller   pod/traefik-68895f75cb-r6hpm                               1/1     Running   0          86m
kube-system          pod/azure-cns-gjnr8                                        2/2     Running   0          93m
kube-system          pod/azure-ip-masq-agent-s4v7h                              1/1     Running   0          93m
kube-system          pod/azure-wi-webhook-controller-manager-5766c6884c-brlgc   1/1     Running   0          93m
kube-system          pod/azure-wi-webhook-controller-manager-5766c6884c-vhw5d   1/1     Running   0          93m
kube-system          pod/cloud-node-manager-k45dg                               1/1     Running   0          93m
kube-system          pod/coredns-5bf45f87d-9nfkk                                1/1     Running   0          93m
kube-system          pod/coredns-5bf45f87d-zrjbc                                1/1     Running   0          92m
kube-system          pod/coredns-autoscaler-7467554f77-xb9v8                    1/1     Running   0          93m
kube-system          pod/csi-azuredisk-node-2467r                               3/3     Running   0          93m
kube-system          pod/csi-azurefile-node-wzvgd                               4/4     Running   0          93m
kube-system          pod/konnectivity-agent-7bb6d76d45-nxjlg                    1/1     Running   0          54m
kube-system          pod/konnectivity-agent-7bb6d76d45-twpd4                    1/1     Running   0          54m
kube-system          pod/konnectivity-agent-autoscaler-5b658f6697-hj7w4         1/1     Running   0          93m
kube-system          pod/kube-proxy-4jtkb                                       1/1     Running   0          93m
kube-system          pod/metrics-server-dff79fd46-9zkpb                         2/2     Running   0          92m
kube-system          pod/metrics-server-dff79fd46-ns9hg                         2/2     Running   0          92m

NAMESPACE   NAME                                               CLASS     HOSTS                                            ADDRESS        PORTS     AGE
argocd      ingress.networking.k8s.io/argocd-server            traefik   argocd.project-x.sbx.vighsandor.az.cubix-pe.hu   9.223.49.134   80, 443   87m
colors      ingress.networking.k8s.io/colors-colors-demo-app   traefik   colors.project-x.sbx.vighsandor.az.cubix-pe.hu   9.223.49.134   80, 443   86m

NAMESPACE   NAME                                        READY   AGE
            clusterissuer.cert-manager.io/letsencrypt   True    86m

NAMESPACE      NAME                                                             TYPE                            DATA   AGE
argocd         secret/argocd-notifications-secret                               Opaque                          0      87m
argocd         secret/argocd-redis                                              Opaque                          1      87m
argocd         secret/argocd-secret                                             Opaque                          1      87m
argocd         secret/argocd-server-tls                                         kubernetes.io/tls               2      85m
argocd         secret/sh.helm.release.v1.argocd-app-cert-manager.v1             helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd-app-cluster-issuer.v1           helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd-app-colors.v1                   helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd-app-external-dns.v1             helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd-app-traefik.v1                  helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd-projects.v1                     helm.sh/release.v1              1      86m
argocd         secret/sh.helm.release.v1.argocd.v1                              helm.sh/release.v1              1      88m
cert-manager   secret/cert-manager-webhook-ca                                   Opaque                          3      86m
cert-manager   secret/letsencrypt-account-key                                   Opaque                          1      86m
colors         secret/colors-tls                                                kubernetes.io/tls               2      85m
external-dns   secret/external-dns                                              Opaque                          1      86m
kube-system    secret/azure-wi-webhook-server-cert                              Opaque                          3      94m
kube-system    secret/bootstrap-token-0kr14c                                    bootstrap.kubernetes.io/token   4      93m
kube-system    secret/konnectivity-certs                                        Opaque                          3      93m
kube-system    secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v46   helm.sh/release.v1              1      3m6s
kube-system    secret/sh.helm.release.v1.aks-managed-overlay-upgrade-data.v47   helm.sh/release.v1              1      56s
kube-system    secret/sh.helm.release.v1.aks-managed-workload-identity.v45      helm.sh/release.v1              1      2m35s
kube-system    secret/sh.helm.release.v1.aks-managed-workload-identity.v46      helm.sh/release.v1              1      21s

NAMESPACE   NAME                           STATUS   AGE
            namespace/argocd               Active   88m
            namespace/cert-manager         Active   86m
            namespace/colors               Active   86m
            namespace/default              Active   94m
            namespace/external-dns         Active   86m
            namespace/ingress-controller   Active   86m
            namespace/kube-node-lease      Active   94m
            namespace/kube-public          Active   94m
            namespace/kube-system          Active   94m

NAMESPACE   NAME                                     SYNC STATUS   HEALTH STATUS
argocd      application.argoproj.io/cert-manager     Synced        Healthy
argocd      application.argoproj.io/cluster-issuer   Synced        Healthy
argocd      application.argoproj.io/colors           Synced        Healthy
argocd      application.argoproj.io/external-dns     Synced        Healthy
argocd      application.argoproj.io/traefik          Synced        Healthy

NAMESPACE   NAME                              AGE
argocd      appproject.argoproj.io/default    87m
argocd      appproject.argoproj.io/platform   86m
argocd      appproject.argoproj.io/product    86m
```

## Managed identity és federated credential

```console
$ az identity list -o table
ClientId                              IsolationScope    Location       Name                       PrincipalId                           ResourceGroup            TenantId
------------------------------------  ----------------  -------------  -------------------------  ------------------------------------  -----------------------  ------------------------------------
ad1808f1-6eab-4c75-a439-21328ca6be52  None              swedencentral  github-repos               7421b6eb-d676-4343-a189-bf32652ee35d  course-baseline          c9b482b1-d17b-430e-bbe6-5d64ba800aa1
8c7d29f6-ba65-4a9c-931a-be0f15099156  None              swedencentral  project-x-sbx-externaldns  9c0c933b-66d3-4494-a34e-7a12786f0f2a  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
fbbae51e-3562-4b6e-9433-49c133e6b756  None              swedencentral  project-x-sbx-aks          6a3921a4-4d5c-4a58-9874-9489cbc3c265  project-x-sbx-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
7e7312df-f535-45ab-a2ee-ba587352896c  None              swedencentral  project-x-sbx-agentpool    a63fabae-928e-4c6e-8cf0-f92b3ab46a85  project-x-sbx-aks-nodes  c9b482b1-d17b-430e-bbe6-5d64ba800aa1
d1e419aa-a7a0-4b12-9042-470c768170b0  None              swedencentral  project-x-dev-externaldns  b4d5e283-b9ed-4267-904e-0d340d0a2c3a  project-x-dev-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
8bd2eac8-b91d-4bdf-afeb-b1a12dda7876  None              swedencentral  project-x-dev-aks          dfd6b057-4be5-431c-b9a8-5f456d39708a  project-x-dev-aks        c9b482b1-d17b-430e-bbe6-5d64ba800aa1
a3402dfc-ed8d-4586-9e20-ac4b228282bf  None              swedencentral  project-x-dev-agentpool    4af64b97-83c6-485a-bb1d-5c6d86185766  project-x-dev-aks-nodes  c9b482b1-d17b-430e-bbe6-5d64ba800aa1
```

```console
$ az identity federated-credential list --resource-group project-x-sbx-aks --identity-name project-x-sbx-externaldns -o table
Issuer                                                                                                                   Name          ResourceGroup      Subject
-----------------------------------------------------------------------------------------------------------------------  ------------  -----------------  -----------------------------------------------
https://swedencentral.oic.prod-aks.azure.com/c9b482b1-d17b-430e-bbe6-5d64ba800aa1/1837ce1a-e53f-40d8-b130-d5a84c1b98fd/  external-dns  project-x-sbx-aks  system:serviceaccount:external-dns:external-dns
```

## Group and role assignment

```console
$ az ad group list -o table
CreatedDateTime       Description                                DisplayName                    IsAssignableToRole    MailEnabled    MailNickname    RenewedDateTime       SecurityEnabled    SecurityIdentifier
--------------------  -----------------------------------------  -----------------------------  --------------------  -------------  --------------  --------------------  -----------------  ----------------------------------------------------
2026-11-22T16:51:35Z  project-x sbx környezet platformadminjai   project-x-sbx-platform-admins  False                 False          75a6d2a9-f      2026-11-22T16:51:35Z  True               S-1-12-1-12839806-1085059002-75819396-2174874129
2026-11-22T16:51:35Z  project-x sbx környezet olvasói            project-x-sbx-readers          False                 False          c9811886-f      2026-11-22T16:51:35Z  True               S-1-12-1-1161050298-1180931574-625530301-1404343192
2026-11-22T16:51:35Z  project-x sbx környezet fejlesztői (írás)  project-x-sbx-developers       False                 False          7e1d0bac-e      2026-11-22T16:51:35Z  True               S-1-12-1-2976719243-1272961042-3302304385-3775884531
2026-11-22T18:09:06Z  project-x dev környezet platformadminjai   project-x-dev-platform-admins  False                 False          74091524-8      2026-11-22T18:09:06Z  True               S-1-12-1-3045378408-1205871726-4192286869-4120062537
2026-11-22T18:09:06Z  project-x dev környezet fejlesztői (írás)  project-x-dev-developers       False                 False          e2dd2da0-6      2026-11-22T18:09:06Z  True               S-1-12-1-3153417266-1089359183-1718794933-686137215
2026-11-22T18:09:06Z  project-x dev környezet olvasói            project-x-dev-readers          False                 False          2d0e760b-2      2026-11-22T18:09:06Z  True               S-1-12-1-3603027198-1109665296-392594604-4218563782
```

```console
$ az role assignment list --all -o table
Principal                                                                       Role                                         Scope
------------------------------------------------------------------------------  -------------------------------------------  --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Owner                                        /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449
platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com  Storage Blob Data Contributor                /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Storage/storageAccounts/platencbvighsandor
ad1808f1-6eab-4c75-a439-21328ca6be52                                            Owner                                        /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449
ad1808f1-6eab-4c75-a439-21328ca6be52                                            Storage Blob Data Contributor                /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/course-baseline/providers/Microsoft.Storage/storageAccounts/platencbvighsandor
8c7d29f6-ba65-4a9c-931a-be0f15099156                                            DNS Zone Contributor                         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-dns/providers/Microsoft.Network/dnsZones/project-x.sbx.vighsandor.az.cubix-pe.hu
fbbae51e-3562-4b6e-9433-49c133e6b756                                            Network Contributor                          /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.Network/virtualNetworks/project-x-sbx-network/subnets/project-x-sbx-aks-nodes
fbbae51e-3562-4b6e-9433-49c133e6b756                                            Contributor                                  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks-nodes
ad1808f1-6eab-4c75-a439-21328ca6be52                                            Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-readers                                                           Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-readers                                                           Azure Kubernetes Service RBAC Reader         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-developers                                                        Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-platform-admins                                                   Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
project-x-sbx-developers                                                        Azure Kubernetes Service RBAC Writer         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-sbx-aks/providers/Microsoft.ContainerService/managedClusters/project-x-sbx
8bd2eac8-b91d-4bdf-afeb-b1a12dda7876                                            Network Contributor                          /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.Network/virtualNetworks/project-x-dev-network/subnets/project-x-dev-aks-nodes
d1e419aa-a7a0-4b12-9042-470c768170b0                                            DNS Zone Contributor                         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-dns/providers/Microsoft.Network/dnsZones/project-x.dev.vighsandor.az.cubix-pe.hu
8bd2eac8-b91d-4bdf-afeb-b1a12dda7876                                            Contributor                                  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks-nodes
project-x-dev-developers                                                        Azure Kubernetes Service RBAC Writer         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
ad1808f1-6eab-4c75-a439-21328ca6be52                                            Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-platform-admins                                                   Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-readers                                                           Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-readers                                                           Azure Kubernetes Service RBAC Reader         /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-platform-admins                                                   Azure Kubernetes Service RBAC Cluster Admin  /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
project-x-dev-developers                                                        Azure Kubernetes Service Cluster User Role   /subscriptions/a6d917d9-aa3b-4f2e-bdbc-d249a8fb8449/resourceGroups/project-x-dev-aks/providers/Microsoft.ContainerService/managedClusters/project-x-dev
```

```console
$ az ad sp list -o table
DisplayName                                      Id                                    AppId                                 CreatedDateTime
-----------------------------------------------  ------------------------------------  ------------------------------------  --------------------
AAD App Management                               f6cb3ff7-cea2-4567-8c29-bf877b098933  f0ae4899-d877-4d3c-ae25-679e38eea492  2026-10-27T18:15:51Z
AAD Request Verification Service - PROD          6b3087ca-09e8-4323-a22f-73217c35edbd  c728155f-7b2a-4502-a08b-b8af9b269319  2026-10-23T11:40:50Z
AADReporting                                     a5cb1554-0354-4e11-a174-a998b76b77eb  1b912ec3-a9dd-4c4d-a53e-76aa7adb28d7  2026-10-27T17:25:22Z
AKS Deployment Safeguards                        09523e38-d2b9-4942-ad5d-2bb4c1b617c5  589ce44b-ca13-4384-89e2-dd4e642a4b37  2026-10-23T15:18:44Z
AKS Trust domain                                 4fe9a917-a24a-469a-bee7-f56a0805773b  4730902d-4371-4615-ba76-e99be524bd44  2026-10-23T15:18:44Z
AfcControlPlane                                  7e4403de-0ce0-46fa-86d0-adcbfddc8f34  56177bc2-12ea-4456-9de3-510ae6f0fcc3  2026-10-23T11:59:22Z
Azure AD Notification                            b16095af-5270-4e6b-9fc6-d6852a7cbc22  fc03f97a-9db0-4627-a216-ec98ce54e018  2026-10-27T00:47:15Z
Azure Bastion                                    a04d2c7c-274b-4df3-8c13-dc7afecf05c0  79d7fb34-4bef-4417-8184-ff713af7a679  2026-10-23T11:59:23Z
Azure Billing Benefits application               0f129780-68f7-4a6f-8778-b118721aaeae  a80a6f8b-55ed-4040-941e-b47c0acb4d4e  2026-10-23T11:46:36Z
Azure Billing Benefits application Prod          fe0d2531-f745-4915-8854-07468ab592b7  4200f961-ba28-4b7b-84f5-090d974ca00c  2026-10-23T11:46:36Z
Azure Cloud Shell                                f6990203-0572-4fa7-97ad-2e45cb22da5f  2233b157-f44d-4812-b777-036cdaf9a96e  2026-10-27T18:31:49Z
Azure Compute                                    e6b5b83f-f7ab-4a36-814d-442d336be5f5  579d9c9d-4c83-4efc-8124-7eba65ed3356  2026-10-23T15:18:08Z
Azure Context Cache RP Prod Identity             b08a19ae-8399-4d8d-815f-8c350f7491b4  89b757f8-1e01-4f41-8c72-75e191b11b8c  2026-11-09T15:29:46Z
Azure Credential Configuration Endpoint Service  7eeb85be-fc6d-4278-a66a-c9926ffe50f1  ea890292-c8c8-4433-b5ea-b09d0668e1a6  2026-10-27T17:25:22Z
Azure DNS                                        8966d66e-166b-4347-a31c-72477c8e9b39  19947cfd-0303-466c-ac3c-fcc19a7a1570  2026-10-23T11:59:23Z
Azure DNS Managed Resolver                       73878e5b-08a4-48b0-9f3f-b36f3a773dc3  b4ca0290-4e73-4e31-ade0-c82ecfaabf6a  2026-10-23T11:59:22Z
Azure ESTS Service                               fae4c730-a2f0-4cfc-b2fc-b3839d900a78  00000001-0000-0000-c000-000000000000  2026-10-23T11:40:44Z
Azure Files                                      9fc9f872-c60a-485f-9ef0-00ecc4bcd11e  69dda2a9-33ca-4ed0-83fb-a9b7b8973ff4  2026-11-09T15:29:46Z
Azure Kubernetes Service - Fleet RP              dd956222-58d3-4328-a509-e8931d57c410  609d2f62-527f-4451-bfd2-ac2c7850822c  2026-10-23T15:18:44Z
Azure Kubernetes Service AAD Server              ea44c353-c74b-49dd-975b-8dc4144c474a  6dae42f8-4368-4678-94ff-3960e28e3630  2026-10-23T15:18:44Z
Azure Linux VM Sign-In                           61ee08a7-dfcb-49a5-95d1-1f78af6d71f6  ce6ff14a-7fdc-4685-bbe0-f6afdfcfa8e0  2026-10-23T15:18:08Z
Azure Management Groups                          3ec435d6-0ac4-44c4-94b6-01f0c974d209  f2c304cf-8e7e-4c3f-8164-16299ad9d272  2026-10-23T11:46:28Z
Azure RBAC Data Plane                            f3521eab-2304-429e-b667-6ced0a73f884  5861f7fb-5582-4c1a-83c0-fc5ffdb531a6  2026-10-23T16:14:04Z
Azure Regional Service Manager                   a7015029-1c45-499e-ac71-220f609702d2  5e5e43d4-54da-4211-86a4-c6e7f3715801  2026-10-23T15:18:07Z
Azure Resource Graph                             82857d41-371c-4651-8e51-17f88dda0b68  509e4652-da8d-478d-a730-e9d4a1996ca4  2026-10-23T11:46:20Z
Azure Resource Manager                           38110152-1a28-4fff-ba4f-4ccf7783e9e2  797f4846-ba00-4fd7-ba43-dac1f8f63013  2026-10-23T11:40:43Z
Azure Signup Api                                 a9a9ace2-fada-47ac-84ac-3e5845b39178  3829f069-1c33-45dd-84ab-2465f4282677  2026-10-23T11:46:30Z
Azure Storage                                    a3f3b44b-8556-4972-91a6-6a2cd5b59112  e406a681-f3d4-42a8-90b6-c2b029497af1  2026-11-09T15:29:46Z
Azure Storage Actions Resource Provider Service  149ff341-dc2e-41e5-8f88-a80fc7b973c5  7d3471e1-ec8b-4655-92f3-bb331362b5ae  2026-11-09T15:29:46Z
Azure Storage Discovery Resource Provider        42897675-693b-4133-a1c7-17952ba1901b  b15f3d14-f6d1-4c0d-93da-d4136c97f006  2026-11-09T15:29:46Z
Azure Support - Network Watcher                  21055295-dbf0-4c4c-a91a-32fecd33ea96  341b7f3d-69b3-47f9-9ce7-5b7f4945fdbd  2026-10-23T11:59:23Z
Azure Traffic Manager and DNS                    13d8c6ad-5506-4845-a6b4-0aa6bec19dd7  2cf9eb86-36b5-49dc-86ae-9a63135dfa8c  2026-10-23T11:59:22Z
Azure Windows VM Sign-In                         931ee855-0d93-4290-8e00-f0d5062e4099  372140e0-b3b7-4226-8ef9-d57986796201  2026-10-23T15:18:08Z
AzureContainerService                            d1253aa5-b314-402c-a926-d8411739f3d2  7319c514-987d-4e9b-ac3d-d38c4f427f4c  2026-10-23T15:18:44Z
AzureDnsFrontendApp                              4f296f8c-6411-43df-b389-8c1c64a96fac  a0be0c72-870e-46f0-9c49-c98333a996f7  2026-10-23T11:59:23Z
AzureFirewallDLPPurview                          70c941f5-1a9f-46b1-b584-49840092b73e  a0765532-5bd5-4891-8a81-49ddbd0242e2  2026-10-23T11:59:22Z
AzureSupportCenter                               555e43d9-bde8-4b4a-ab43-05461fc5ece9  37182072-3c9c-4f6a-a4b3-b3f91cacffce  2026-10-23T11:40:50Z
AzureVirtualNetworkManager                       51f5ea28-6a11-4d31-8d28-edeac054afb3  6d057c82-a784-47ae-8d12-ca7b38cf06b4  2026-10-23T11:59:23Z
Benefit Experiences                              960ce560-ce84-4d0e-aef5-06f8b024bc28  427ebe87-64e9-467b-9c5d-fc88b087e227  2026-10-23T11:46:36Z
Billing RP                                       a2660642-5caf-448f-8570-1a169c065aef  80dbdb39-4f33-4799-8b6f-711b5e3e61b6  2026-10-23T11:48:38Z
CABProvisioning                                  026b3eee-592d-4b44-a4f5-64aebe4959c3  5da7367f-09c8-493e-8fd4-638089cddec3  2026-10-23T11:46:09Z
Capacity                                         0ebc17b1-f464-49ce-9c51-e949e5e0ee88  fbc197b7-9e9c-4f98-823f-93cb1cb554e6  2026-10-23T15:19:15Z
Compute Artifacts Publishing Service             89135be0-c975-49e1-9211-8514d49c0dcd  a8b6bf88-1d1a-4626-b040-9a729ea93c65  2026-10-23T15:18:08Z
Compute Image Registry                           5af989d0-24e5-4439-bfe1-07fd3feeca29  51b6191a-b045-44cf-8277-ee37c9fb5a06  2026-10-23T15:18:08Z
Compute Recommendation Service                   ed2d9327-882d-495a-9006-232b461ed5d9  b9a92e36-2cf8-4f4e-bcb3-9d99e00e14ab  2026-10-23T15:18:08Z
Compute Usage Provider                           ea5cbd76-c8c2-4c06-9e81-5d4aa35d6d78  a303894e-f1d8-4a37-bf10-67aa654a0596  2026-10-23T15:18:08Z
GatewayRP                                        faa91a10-7476-4a46-bb3d-eb1ce79ff3a6  486c78bf-a0f7-45f1-92fd-37215929e116  2026-10-23T11:59:23Z
IAM Supportability                               891fa6d1-f752-464a-87b9-3fec23db575f  a57aca87-cbc0-4f3c-8b9e-dc095fdc8978  2026-10-23T11:40:50Z
MCAPI Authorization Prod                         ea8f347c-2882-4532-9295-c636f159241a  d73f4b35-55c9-48c7-8b10-651f6f2acb2e  2026-10-23T11:40:50Z
MS-PIM                                           bd19ba9c-aa94-42ad-9daa-e88c1a89855b  01fc33a7-78ba-4d2f-a4b7-768e336e890e  2026-10-23T11:49:47Z
Managed Disks Resource Provider                  4bf868da-02d7-437a-94d6-ea52e88b25f5  60e6cd67-9c8c-4951-9b3c-23c25a2169af  2026-10-23T15:18:08Z
Managed Service Identity                         4d78ddf8-7f77-4736-ae31-e1bc92730681  ef5d5c69-a5df-46bb-acaf-426f161a21a2  2026-10-23T15:40:23Z
Microsoft App Access Panel                       b0824186-3c89-4f61-8457-c4ce670d0e94  0000000c-0000-0000-c000-000000000000  2026-10-23T11:40:42Z
Microsoft Approval Management                    d3538985-091b-47a5-bb3f-4702c7645754  65d91a3d-ab74-42e6-8a2f-0add61688c74  2026-10-27T17:29:29Z
Microsoft Authorization Service Dataplane        2fd6b0af-fffe-4384-ab58-afad1e1154bc  89e7f920-bdc3-4e71-99e5-30d84827b610  2026-10-23T11:45:59Z
Microsoft Azure IPAM                             7adbdfa5-e658-4189-b0c5-3ff10cf90247  60b2e7d5-a27f-426d-a6b1-acced0846fdf  2026-10-23T11:59:24Z
Microsoft Azure Network Copilot                  829b5ea3-85f8-4d90-9041-58111d64ef83  40c49ff3-c6ae-436d-b28e-b8e268841980  2026-10-23T11:59:22Z
Microsoft Azure Signup Portal                    36559f00-6a15-494a-80f8-4b8f834940e4  8e0e8db5-b713-4e91-98e6-470fed0aa4c2  2026-10-23T11:45:42Z
Microsoft Azure Vnet Verifier                    96db6edf-0b42-4885-a946-8a6bb7fcf7fd  6e02f8e9-db9b-4eb5-aa5a-7c8968375f68  2026-10-23T11:59:23Z
Microsoft Commerce Accounts Service              a4d4cd2f-7aad-47a6-9ffa-0a83f2c2ce0f  bf9fc203-c1ff-4fd4-878b-323642e462ec  2026-10-23T11:45:15Z
Microsoft Graph                                  3ec35064-ea83-4184-84f3-37dd5a9cde87  00000003-0000-0000-c000-000000000000  2026-10-23T11:40:44Z
Microsoft Graph Change Tracking                  edff3599-ad26-4e0e-b3ea-ddd7c1983687  0bf30f3b-4a52-48df-9a82-234910c4a086  2026-10-23T11:40:50Z
Microsoft Modern Contact Master                  5e5b41b4-2912-48f8-a0b1-f43a90f71fd8  224a7b82-46c9-4d6b-8db0-7360fb444681  2026-10-23T12:17:02Z
Microsoft.SMIT                                   f1742bf5-5d83-487e-b91c-37f462b16095  8fca0a66-c008-4564-a876-ab3ae0fd5cff  2026-10-23T11:40:50Z
Microsoft_Azure_Support                          078c4a35-9e95-4354-bc0d-07a464b57f06  959678cf-d004-4c22-82a6-d2ce549a58b8  2026-10-26T17:28:37Z
NFV Resource Provider                            7bcef83b-e8d2-4dd8-8b62-70414e01403a  328fd23b-de6e-462c-9433-e207470a5727  2026-10-23T11:59:23Z
Narada Notification Service                      aa38ae46-bea7-4f37-bed1-43fa483f36bc  51b5e278-ed7e-42c6-8787-7ff93e92f577  2026-11-09T14:00:36Z
Network Watcher                                  244777bf-b99b-4b0e-910b-6fe148010c41  7c33bfcb-8d33-48d6-8e60-dc6404003489  2026-10-23T11:59:22Z
NetworkTrafficAnalyticsService                   9bfb912f-9463-4d6c-9ebf-85271f2a86f1  1e3e4475-288f-4018-a376-df66fd7fac5f  2026-10-23T11:59:23Z
Office 365 Configure                             02891449-ead8-46e4-85fa-35ac7e124095  aa9ecb1e-fd53-4aaa-a8fe-7a54de2c1334  2026-10-23T11:40:43Z
OneCert-AzureDns-Prod                            284cdc26-d20e-4951-b3f4-4c007380e0ed  3471ca03-f150-4759-88e6-0bfc97daf723  2026-10-23T11:59:24Z
Policy Administration Service                    1abbb248-14c6-422e-820e-7fd1c3a75ad9  0469d4cd-df37-4d93-8a61-f8c75b809164  2026-10-23T11:46:26Z
Quota Service Core - ARM Client                  41f08e86-92f3-4264-b5a7-f4e690b2fadd  3cf468b4-12a0-43cd-aa3f-3f39210d14cf  2026-10-23T15:18:08Z
RPSaaS Meta RP                                   360666d4-aa0f-4dc8-8d48-2e4688ae9163  f77c2a8f-8a0a-4776-8e0a-bcb2549610ca  2026-10-23T11:59:22Z
ScheduledActions                                 7296dc4b-1e58-49c0-b65c-0893c8012cf9  45164d96-544d-4a64-a1ca-3fb4bbb6eb18  2026-10-23T15:18:08Z
Signup                                           0ad839c0-cf14-420b-bf83-c37029fb55b7  b4bddae8-ab25-483e-8670-df09b9f1d0ea  2026-10-23T11:40:43Z
Storage Data Management RP Prod FPA              f100cead-99e2-414a-b7c7-8ef89a00b372  3a3b6b87-84e2-4ad2-aa37-d76c339371a4  2026-11-09T15:29:46Z
Storage Resource Provider                        1f4fbb20-2ade-47da-9f62-ebead483c4e0  a6aa9161-5291-40bb-8c5c-923b567bee3b  2026-11-09T15:29:46Z
SubscriptionRP                                   faedc605-d4d8-425e-97e5-750e4387d3f9  e3335adb-5ca0-40dc-b8d3-bedc094e523b  2026-10-23T11:46:09Z
Windows Azure Active Directory                   4285e6a9-9347-46b0-9a42-ca1a8d9b8c6d  00000002-0000-0000-c000-000000000000  2026-10-23T11:40:42Z
Workload Identity Control Plane                  94a5d03c-74ac-434c-babd-8f994ff3016c  2d4e7d66-4baf-4714-bf99-7e03dc377fdb  2026-10-23T11:45:59Z
aciapi                                           00a5be0e-2948-4d9c-9948-677f02bca13d  c5b17a4f-cc6f-4649-9480-684280a2af3a  2026-10-23T11:48:40Z
github-repos                                     7421b6eb-d676-4343-a189-bf32652ee35d  ad1808f1-6eab-4c75-a439-21328ca6be52  2026-11-21T17:45:33Z
networkcopilotRP                                 8a0ce803-94cb-4b75-aaaf-8c9dae9688a2  d66e9e8e-53a4-420c-866d-5bb39aaea675  2026-10-23T11:59:22Z
project-x-dev-agentpool                          4af64b97-83c6-485a-bb1d-5c6d86185766  a3402dfc-ed8d-4586-9e20-ac4b228282bf  2026-11-22T18:10:53Z
project-x-dev-aks                                dfd6b057-4be5-431c-b9a8-5f456d39708a  8bd2eac8-b91d-4bdf-afeb-b1a12dda7876  2026-11-22T18:09:32Z
project-x-dev-argocd                             adbc8abc-039c-4290-a3ee-8f2993b685d1  5066014b-984c-458b-bdbf-a95110bd3edb  2026-11-22T18:23:35Z
project-x-dev-externaldns                        b4d5e283-b9ed-4267-904e-0d340d0a2c3a  d1e419aa-a7a0-4b12-9042-470c768170b0  2026-11-22T18:09:32Z
project-x-sbx-agentpool                          a63fabae-928e-4c6e-8cf0-f92b3ab46a85  7e7312df-f535-45ab-a2ee-ba587352896c  2026-11-22T16:53:28Z
project-x-sbx-aks                                6a3921a4-4d5c-4a58-9874-9489cbc3c265  fbbae51e-3562-4b6e-9433-49c133e6b756  2026-11-22T16:52:02Z
project-x-sbx-argocd                             a464a9a5-0b90-42ad-870e-49f8ea66b10a  b6cc0e75-ca3f-4eff-8af1-7c744111b6bb  2026-11-22T16:52:15Z
project-x-sbx-externaldns                        9c0c933b-66d3-4494-a34e-7a12786f0f2a  8c7d29f6-ba65-4a9c-931a-be0f15099156  2026-11-22T16:52:02Z
ptm-cp-prod                                      a2d5bbfb-241c-4f9a-92b4-71474f8cd6f3  1387301c-59b7-4204-84b8-1b7559500626  2026-10-23T11:59:22Z
ptm-prod                                         2d09e82d-6b93-4164-99cc-9c16ee8b36d5  9bc4cc98-c5f0-4916-b2ef-b55848ef0f48  2026-10-23T11:59:22Z
```

## Tarraform

```console
$ terraform state list
data.azuread_service_principal.member["github-repos"]
data.azuread_user.member["platformengineer_vighsandor.hu#EXT#@platformengineervighsandor.onmicrosoft.com"]
data.azurerm_client_config.current
data.azurerm_dns_zone.parent
azuread_application.argocd
azuread_application_federated_identity_credential.argocd
azuread_group.env["developers"]
azuread_group.env["platform_admins"]
azuread_group.env["readers"]
azuread_group_member.env["developers/vighsandor"]
azuread_group_member.env["platform_admins/sp:github-actions"]
azuread_group_member.env["platform_admins/vighsandor"]
azuread_group_member.env["readers/vighsandor"]
azurerm_dns_ns_record.delegation
azurerm_dns_zone.env
azurerm_federated_identity_credential.external_dns
azurerm_kubernetes_cluster.aks
azurerm_resource_group.aks
azurerm_resource_group.dns
azurerm_role_assignment.aks["developers-cluster_user"]
azurerm_role_assignment.aks["developers-writer"]
azurerm_role_assignment.aks["platform_admins-cluster_admin"]
azurerm_role_assignment.aks["platform_admins-cluster_user"]
azurerm_role_assignment.aks["readers-cluster_user"]
azurerm_role_assignment.aks["readers-reader"]
azurerm_role_assignment.aks_pipeline["github-actions"]
azurerm_role_assignment.aks_subnet_network_contributor
azurerm_role_assignment.external_dns_zone_contributor
azurerm_subnet.aks_nodes
azurerm_user_assigned_identity.aks
azurerm_user_assigned_identity.external_dns
azurerm_virtual_network.aks
helm_release.argocd
helm_release.argocd_app["cert-manager"]
helm_release.argocd_app["cluster-issuer"]
helm_release.argocd_app["colors"]
helm_release.argocd_app["external-dns"]
helm_release.argocd_app["traefik"]
helm_release.argocd_projects
terraform_data.request
terraform_data.workspace_guard
time_sleep.argocd_app_cleanup
time_sleep.rbac_propagation
```
