# Bootstrap and Disaster Recovery

> Procedures for initial cluster setup and recovery from disasters

## Initial Cluster Setup

```bash
# 1. Generate Talos configuration
task talos:generate-clusterconfig

# 2. Apply Talos configuration to nodes
task talos:apply-clusterconfig

# 3. Bootstrap Talos cluster
task k8s-bootstrap:talos-cluster

# 4. Deploy CRDs and core apps
task k8s-bootstrap:apps
```

## Bootstrap Phases

1. **CRDs** (00-crds.yaml): external-dns, gateway-api, keda, prometheus, external-secrets
2. **Core Apps** (01-apps.yaml): cilium, coredns, cert-manager, flux-operator, cloudnative-pg, rook-ceph
3. **Doppler Integration**: Inject service token for external-secrets
4. **Flux Sync**: Flux automatically reconciles cluster-apps/

## Recovery from Disaster

1. Restore Talos cluster from backup configuration
2. Bootstrap core infrastructure (CRDs + apps)
3. Restore Doppler token
4. Flux will reconcile applications
5. Volsync will restore PVCs from B2/MinIO
6. CloudNative-PG will restore databases from WAL

## Troubleshooting Bootstrap

### Talos Issues

```bash
# Check node status
talosctl -n <node-ip> dashboard

# View logs
talosctl -n <node-ip> logs

# Reset node
talosctl -n <node-ip> reset --graceful=false --reboot
```

### Flux Bootstrap Issues

```bash
# Check Flux components
kubectl get pods -n flux-system

# Force reconcile
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Re-bootstrap if needed
flux uninstall
# Then re-run: task k8s-bootstrap:apps
```

### Doppler Token Issues

```bash
# Verify token exists
kubectl get secret doppler-token -n external-secrets

# Re-create if missing
kubectl create secret generic doppler-token \
  --from-literal=dopplerToken=<token> \
  -n external-secrets
```
