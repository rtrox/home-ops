export PROMETHEUS_OPERATOR_VERSION=v0.71.2
kubectl create ns flux-system
kubectl apply --server-side --filename https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
kubectl apply --server-side --filename https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
kubectl apply --server-side --filename https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml
kubectl apply --server-side --filename https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
sops -d sops-age.bty.yaml | kubectl apply --server-side --filename -
sops -d ../flux/vars/cluster-secrets.bty.yaml | kubectl apply --server-side --filename -
kubectl apply --server-side --kustomize ./
kubectl apply --server-side --kustomize ../flux/config