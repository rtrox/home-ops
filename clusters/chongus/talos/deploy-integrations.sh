#!/usr/bin/env bash
# shellcheck disable=2312
pushd integrations >/dev/null 2>&1 || exit 1

if [ -z "${IPV6_POD_CIDR}" ]; then
  echo "env var IPV6_POD_CIDR is not set"
  exit 1
fi
rm -rf cni/charts
envsubst < ../../../../cluster-cd/apps/chongus/kube-system/cilium/app/values.yaml > cni/values.yaml
kustomize build --enable-helm cni | kubectl apply -f -
rm cni/values.yaml
rm -rf cni/charts

rm -rf kubelet-csr-approver/charts
envsubst < ../../../../cluster-cd/apps/chongus/system-controllers/kubelet-csr-approver/app/values.yaml > kubelet-csr-approver/values.yaml
if ! kubectl get ns system-controllers >/dev/null 2>&1; then
  kubectl create ns system-controllers
fi
kustomize build --enable-helm kubelet-csr-approver | kubectl apply -f -
rm kubelet-csr-approver/values.yaml
rm -rf kubelet-csr-approver/charts

envsubst < ../../../../cluster-cd/apps/chongus/kube-system/coredns/app/values.yaml > coredns/values.yaml
kustomize build --enable-helm coredns | kubectl apply -f -
rm coredns/values.yaml
rm -rf coredns/charts