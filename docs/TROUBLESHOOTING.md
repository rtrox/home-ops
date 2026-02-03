# Troubleshooting Guide

> Common issues and debugging procedures for home-ops clusters

## Flux Issues

```bash
# Check Flux controller status
kubectl get kustomization -A
kubectl get helmrelease -A

# View reconciliation details
kubectl describe kustomization <name> -n <namespace>
kubectl describe helmrelease <name> -n <namespace>

# Controller logs
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller
kubectl logs -n flux-system deploy/source-controller

# Force reconciliation
flux reconcile kustomization <name>
flux reconcile helmrelease <name> -n <namespace>
```

## HelmRelease Failures

- Check `status.conditions` for error messages
- Verify OCIRepository can pull chart: `kubectl get ocirepository <name>`
- Check values rendering: `helm template` locally
- Review secret availability if using ExternalSecrets

## ExternalSecrets Issues

```bash
# Check ClusterSecretStore
kubectl get clustersecretstore doppler -o yaml

# Check ExternalSecret status
kubectl describe externalsecret <name> -n <namespace>

# Verify Doppler token
kubectl get secret doppler-token -n external-secrets -o yaml

# Force refresh
kubectl annotate externalsecret <name> force-sync=$(date +%s)
```

## Storage Issues

```bash
# Ceph cluster health
kubectl get cephcluster -n rook-ceph
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

# PVC status
kubectl get pvc -A
kubectl describe pvc <name> -n <namespace>

# Volsync replication
kubectl get replicationsource -A
kubectl get replicationdestination -A
```

## Network Issues

```bash
# Cilium status
cilium status

# Gateway status
kubectl get gateway -A
kubectl get httproute -A

# DNS records
kubectl get dnsendpoint -A

# Certificate status
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
```

## Node Issues

```bash
# Talos node status
talosctl -n <node-ip> dashboard

# Node resources
kubectl top nodes
kubectl describe node <node-name>

# GPU availability (Chongus only)
kubectl describe node | grep -A 5 nvidia.com/gpu
```
