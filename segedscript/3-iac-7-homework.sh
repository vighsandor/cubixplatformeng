#!/bin/bash

az group list -o table
az aks list -o table
az network vnet list --resource-group project-x-sbx-aks-nodes -o table
az network dns zone list

# A bejegyzett DNS nevek listája
az network dns record-set list --resource-group project-x-sbx-dns --zone-name <domain> -o table

# Kubernetesen belüli erőforrások listája és státusza
kubectl get -A pods,ingress,ClusterIssuer,secrets,namespace

# Managed identity és federated credential
az identity list -o table
az identity federated-credential list --resource-group project-x-sbx-aks --identity-name project-x-hw-externaldns -o table

# Group and role assignment
az ad group list -o table
az role assignment list --all -o table

# Tarraform
terraform state list
