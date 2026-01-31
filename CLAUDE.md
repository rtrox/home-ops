# Home-Ops Repository Context

> **Important**: This document should be kept up-to-date with each significant architectural change to ensure AI agents and contributors have accurate context.

## Overview

This repository implements a GitOps-managed Kubernetes infrastructure using FluxCD, running two clusters: Chongus (primary, modern pattern) and Bitty (secondary, being phased out). The infrastructure is built on Talos Linux with a focus on automation, high availability, and disaster recovery.

## Table of Contents

1. [Cluster Specifications](#cluster-specifications)
2. [Repository Structure](#repository-structure)
3. [Application Structure](#application-structure)
4. [Technology Stack](#technology-stack)
5. [Common Patterns](#common-patterns)
6. [Anti-Patterns](#anti-patterns)
7. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
8. [Network Architecture](#network-architecture)
9. [Monitoring and Alerting](#monitoring-and-alerting)
10. [Testing and Validation](#testing-and-validation)
11. [Troubleshooting Guide](#troubleshooting-guide)
12. [Bootstrap Process](#bootstrap-process)
13. [Common Operations](#common-operations)
14. [Key Principles](#key-principles)

## Cluster Specifications

### Chongus Cluster (Primary - NEW PATTERN - FOLLOW THIS)

**Hardware:**

- 3 Dell R730 nodes (all roles: control-plane + worker)
- IP Range: 172.30.11.1-3
- Architecture: amd64 Intel with NVIDIA GPUs
- GPU Support: nvidia-container-toolkit, production drivers, suitable for GPU workloads
- Talos v1.10.6 / Kubernetes 1.33.0
- Pod CIDR: 10.244.0.0/16
- Service CIDR: 10.96.0.0/12

**Storage:**

- **Rook-Ceph**: 6x Samsung 870 EVO 2TB SSDs (2 per node)
  - Storage Class: `ceph-block` (default for persistent data)
  - Replication: 3 replicas, host-level failure domain
  - Compression: aggressive zstd
  - Features: layering, fast-diff, object-map, deep-flatten, exclusive-lock
- **OpenEBS LocalPV**: `/var/mnt/local-hostpath`
  - Storage Class: `openebs-hostpath`
  - Purpose: Local caching for Volsync operations
- **NFS**: Direct mounts to nas.rtrox.io for shared storage

**Network:**

- Cilium CNI with Gateway API support
- Load Balancer IPAM: 172.22.12.0/24 (Cilium LBIPAM)
- Envoy Gateway for HTTP routing
- External DNS with Cloudflare integration

**Use Cases:**

- GPU-accelerated workloads (ML, transcoding with NVIDIA)
- Larger workloads requiring more resources
- Primary production applications

### Bitty Cluster (Secondary - OLD PATTERN - BEING PHASED OUT)

**Hardware:**

- 3 Intel NUC nodes (newer CPUs, fewer cores than Chongus)
- IP Range: 172.30.21.1-3
- NVMe storage (faster than Chongus SSDs)
- Intel iGPU with QuickSync (no discrete GPUs)
- Talos v1.10.1 / Kubernetes 1.33.0

**Use Cases:**

- Video transcoding via QuickSync (Intel iGPU)
- Smaller workloads
- Being migrated to Chongus pattern

**Migration Status:**

- Resources should be migrated FROM Bitty TO Chongus
- Bitty will eventually match Chongus setup pattern
- Do not deploy new applications to Bitty

## Repository Structure

```
/home/rtrox/home-ops/
├── ansible/                    # Non-k8s machines (Raspberry Pis)
│   └── roles/
├── cluster-apps/               # Main FluxCD source (ACTIVE)
│   ├── base/                   # Shared across clusters
│   │   └── [app]/app/         # Cross-cluster applications
│   ├── chongus/               # Chongus-specific apps (NEW PATTERN)
│   │   └── [namespace]/       # Organized by namespace
│   │       └── [app]/         # Application directory
│   │           ├── app/       # HelmRelease + configs
│   │           └── ks.yaml    # Flux Kustomization
│   ├── bitty/                 # Bitty-specific (deprecated pattern)
│   └── components/            # Reusable Kustomize components
│       ├── flux/alerts/       # Flux error notifications
│       ├── namespace/         # Basic namespace template
│       ├── privileged-namespace/  # Privileged workload namespace
│       └── volsync/           # PVC + backup templates
├── cluster-cd/                 # Legacy structure (DO NOT USE)
├── clusters/                   # Cluster definitions & bootstrap
│   ├── chongus/
│   │   ├── bootstrap/         # Helmfile-based bootstrap
│   │   │   ├── helmfile.d/    # 00-crds.yaml, 01-apps.yaml
│   │   │   ├── resources/
│   │   │   └── templates/
│   │   ├── flux/              # Flux Kustomizations
│   │   │   └── cluster/
│   │   └── talos/             # Talos configuration
│   │       └── clusterconfig/
│   └── bitty/                 # Old bootstrap pattern (deprecated)
└── .taskfiles/                # Operational automation
    ├── k8s-bootstrap/
    ├── sops/
    └── talos/
```

## Application Structure

Every application in the Chongus cluster follows this standard structure:

```
[namespace]/
└── [appname]/
    ├── app/
    │   ├── helmrelease.yaml      # Helm chart deployment
    │   ├── ocirepository.yaml    # Per-app chart source
    │   ├── externalsecret.yaml   # Doppler secret integration (optional)
    │   ├── kustomization.yaml    # Kustomize resources
    │   └── config/               # ConfigMap sources (optional)
    │       └── [config-files]
    └── ks.yaml                   # Flux Kustomization (orchestrator)
```

**Key Files:**

- `ks.yaml`: `kustomize.toolkit.fluxcd.io/v1` Kustomization (Flux resource)
- `kustomization.yaml`: `kustomize.config.k8s.io/v1beta1` Kustomization (Kustomize resource)
- Components included via `components:` field in `ks.yaml`

## Technology Stack

### New Pattern (Chongus - FOLLOW THIS)

**HTTP Routing:**

- Gateway API with Envoy Gateway
- HTTPRoute resources for ingress
- Two gateways:
  - **`envoy-external` (172.22.12.2)**: Connected to Cloudflare Tunnel, internet-accessible
  - **`envoy-internal` (172.22.12.1)**: Local network only (accessible via Tailscale)
- **Default Preference**: Use `envoy-internal` unless internet access is explicitly needed by the user
- TLS certificates via cert-manager with Let's Encrypt

**Helm Charts:**

- OCIRepository per application (even if multiple apps use the same chart)
- Chart references: `chartRef.kind: OCIRepository`
- No centralized HelmRepository objects

**Secrets Management:**

- Doppler as primary secret store
- ExternalSecrets operator with ClusterSecretStore
- SOPS only for bootstrap secrets (considered tech debt)
- NO postBuild substitution from SOPS secrets

**Configuration:**

- Components for reusable patterns (namespace, volsync, alerts)
- Flux Kustomization for orchestration
- postBuild substitution from ExternalSecrets when needed (minimal)

**Task Automation:**

- Taskfiles in `.taskfiles/` directory
- No scattered shell scripts

**Storage Classes:**

- `ceph-block`: Persistent application data (default)
- `openebs-hostpath`: Local cache/temp storage
- NFS mounts: Direct to NAS (nas.rtrox.io)

### Old Pattern (Bitty - AVOID FOR NEW WORK)

**HTTP Routing:**

- Ingress-Nginx controller
- Ingress resources

**Helm Charts:**

- Centralized HelmRepository at `clusters/bitty/flux/repositories/`
- HelmChart resources reference shared repositories

**Secrets Management:**

- Centralized SOPS secret: `clusters/bitty/flux/vars/cluster-secrets.bty.yaml`
- postBuild substitution from SOPS secrets
- Mixed with ExternalSecrets (inconsistent)

**Configuration:**

- Direct manifest references in Kustomizations
- No component pattern

**Task Automation:**

- Shell scripts scattered in various locations

## Common Patterns

### HelmRelease Structure

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: app-name
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: chart-name
  values:
    controllers:
      main:
        annotations:
          reloader.stakater.com/auto: "true"  # Auto-reload on ConfigMap/Secret change
        containers:
          main:
            image:
              repository: ghcr.io/org/image
              tag: v1.2.3@sha256:abc123...  # ALWAYS pin to SHA256
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                memory: 512Mi  # Memory limit is REQUIRED
```

### OCIRepository Pattern

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: chart-name
spec:
  interval: 1h
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 1.2.3  # Chart version
  url: oci://registry.example.com/charts/chart-name
```

### ExternalSecret Pattern

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-secret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler
  target:
    name: app-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        KEY_NAME: "{{ .doppler_key_name }}"
  dataFrom:
    - extract:
        key: DOPPLER_SECRET_NAME  # Extract all keys from Doppler secret
  data:
    - secretKey: local_key
      remoteRef:
        key: DOPPLER_KEY  # Extract specific key from Doppler
```

### Volsync Backup Pattern

```yaml
# In ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-name
spec:
  path: ./cluster-apps/chongus/namespace/app-name/app
  components:
    - ../../../components/volsync  # Include Volsync backup
  postBuild:
    substitute:
      APP: app-name
      VOLSYNC_CAPACITY: 10Gi
      VOLSYNC_CLAIM: app-name
```

**Backup Backends:**

- **B2 (Backblaze)**: Daily backups, 7-day retention
- **MinIO**: Hourly backups, 24h/7d/5w retention
- Both use Restic with S3 protocol

### Gateway API Pattern

```yaml
# HTTPRoute in HelmRelease values
route:
  main:
    hostnames:
      - app.rtrox.io
    parentRefs:
      - name: envoy-internal  # Prefer envoy-internal unless internet access needed
        namespace: network
        sectionName: https
    rules:
      - matches:
          - path:
              type: PathPrefix
              value: /
        backendRefs:
          - name: app-name-main
            port: 8080
```

### Component Usage

```yaml
# In Flux Kustomization
components:
  - ../../../components/namespace            # Basic namespace
  - ../../../components/privileged-namespace # For privileged workloads
  - ../../../components/volsync              # PVC + backup
  - ../../../components/flux/alerts          # Error notifications
```

## Anti-Patterns (DO NOT USE)

1. **Centralized HelmRepository** - Each app should have its own OCIRepository
2. **SOPS for application secrets** - Use ExternalSecrets + Doppler instead
3. **postBuild substitution from SOPS** - Use ExternalSecrets or direct values
4. **Direct manifest references** - Use components for reusable patterns
5. **Shell scripts for automation** - Use Taskfiles instead
6. **Ingress resources** - Use Gateway API HTTPRoute
7. **Storing secrets in Git** - Even encrypted, prefer ExternalSecrets
8. **cluster-cd/ directory** - Use cluster-apps/ instead
9. **Mutable image tags** - Always pin to SHA256 digest
10. **Missing resource limits** - All containers must have memory limits
11. **Raw manifests over Helm charts** - Prefer Helm charts for easier Flux management (not a hard rule, but best practice)
12. **Velero for backups** - Use Volsync instead (Velero is legacy/deprecated)
13. **envoy-external for internal apps** - Prefer envoy-internal unless internet access is explicitly needed

## Backup and Disaster Recovery

### Volsync Strategy (PRIMARY MECHANISM)

- **Dual-backend**: B2 (daily) + MinIO (hourly)
- **Cache storage**: openebs-hostpath (4Gi per app)
- **Source storage**: ceph-block with snapshots
- **Restoration**: Manual trigger via `restore-once` annotation
- **Status**: Active, preferred backup mechanism for all stateful workloads

### CloudNative-PG (PostgreSQL)

- **HA**: 3-node cluster with streaming replication
- **Backup**: WAL archiving to MinIO
- **Retention**: 14 days
- **Compression**: bzip2 for data and WAL
- **Schedule**: Daily (@daily) + immediate on creation

## Network Architecture

### Cilium CNI

- **IPAM**: Kubernetes mode (10.244.0.0/16)
- **Routing**: Native routing with auto-direct node routes
- **Load Balancer**: Maglev algorithm, DSR (Direct Server Return) mode
- **KubeProxy**: Replaced by eBPF
- **Features**: BBR bandwidth manager, IPv4 BigTCP, Gateway API support
- **Observability**: Hubble UI and relay enabled

### Load Balancer IP Allocation

- **Pool**: 172.22.12.0/24 (Cilium LBIPAM)
- **External Gateway**: 172.22.12.2 (Cloudflare Tunnel, internet-accessible)
- **Internal Gateway**: 172.22.12.1 (Local network, Tailscale-accessible)

### DNS

- **External-DNS**: Cloudflare provider
- **Sources**: Service, Gateway HTTPRoute, CRD
- **Policy**: Sync (create/update/delete records)
- **Integration**: Automatic DNS via Gateway API annotations

### Certificates

- **Issuer**: Let's Encrypt (cert-manager)
- **Storage**: Kubernetes Secret resources
- **Automation**: cert-manager + external-dns
- **TLS**: Gateway API tls.certificateRefs

## Monitoring and Alerting

### Prometheus Stack

- **Retention**: 14 days local, long-term via Thanos
- **Storage**: 55Gi ceph-block
- **Scrape interval**: 1m
- **Thanos**: S3 backend (MinIO) with compression
- **Resources**: 100m CPU request, 2Gi memory limit

### Components

- **Alertmanager**: 1Gi storage, 5m resolve timeout
- **Grafana**: Separate deployment
- **Loki**: Log aggregation
- **Alloy**: Log collection
- **Exporters**: blackbox, node, kube-state-metrics, custom (awair, graphite)

### Alerts

- **Flux errors**: Automatic notifications to Alertmanager
- **PrometheusRule**: Custom rules for Volsync, CNPG, Flux

## Testing and Validation

### Pre-commit Hooks

- Trailing whitespace removal
- End-of-file fixing
- YAML linting (.github/lint/.yamllint.yaml)
- SOPS secret prevention

### GitHub Actions CI

1. **Pre-commit checks**: Run hooks on changed files
2. **YAML lint**: Validate all YAML syntax
3. **Renovate validation**: Check Renovate config
4. **Flux-local test**: Dry-run all Kustomizations and HelmReleases
5. **Flux-local diff**: Generate PR diffs for review

### Local Validation

```bash
# Validate Flux resources
task flux:validate

# Test Talos configuration
task talos:generate-clusterconfig

# Bootstrap dry-run
helmfile --file clusters/chongus/bootstrap/helmfile.d/00-crds.yaml diff
```

## Troubleshooting Guide

### Flux Issues

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

### HelmRelease Failures

- Check `status.conditions` for error messages
- Verify OCIRepository can pull chart: `kubectl get ocirepository <name>`
- Check values rendering: `helm template` locally
- Review secret availability if using ExternalSecrets

### ExternalSecrets Issues

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

### Storage Issues

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

### Network Issues

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

### Node Issues

```bash
# Talos node status
talosctl -n <node-ip> dashboard

# Node resources
kubectl top nodes
kubectl describe node <node-name>

# GPU availability (Chongus only)
kubectl describe node | grep -A 5 nvidia.com/gpu
```

## Bootstrap Process

### Initial Cluster Setup

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

**Bootstrap Phases:**

1. **CRDs** (00-crds.yaml): external-dns, gateway-api, keda, prometheus, external-secrets
2. **Core Apps** (01-apps.yaml): cilium, coredns, cert-manager, flux-operator, cloudnative-pg, rook-ceph
3. **Doppler Integration**: Inject service token for external-secrets
4. **Flux Sync**: Flux automatically reconciles cluster-apps/

### Recovery from Disaster

1. Restore Talos cluster from backup configuration
2. Bootstrap core infrastructure (CRDs + apps)
3. Restore Doppler token
4. Flux will reconcile applications
5. Volsync will restore PVCs from B2/MinIO
6. CloudNative-PG will restore databases from WAL

## Common Operations

### Adding a New Application (Chongus Pattern)

1. Create directory: `cluster-apps/chongus/[namespace]/[app-name]/`
2. Create `app/` subdirectory
3. Add `helmrelease.yaml` with chartRef to OCIRepository
4. Add `ocirepository.yaml` for chart source
5. Add `externalsecret.yaml` if secrets needed
6. Add `kustomization.yaml` listing resources
7. Add `ks.yaml` Flux Kustomization with dependencies
8. Add `ks.yaml` to parent namespace `kustomization.yaml`
9. Commit and push - Flux will reconcile

### Migrating App from Bitty to Chongus

1. Review Bitty app configuration
2. Convert Ingress to HTTPRoute
3. Convert HelmRepository ref to OCIRepository
4. Move SOPS secrets to Doppler + ExternalSecret
5. Remove postBuild substitution from SOPS
6. Add components for namespace/volsync if needed
7. Deploy to Chongus
8. Test thoroughly
9. Remove from Bitty

### Updating Application

1. Update image tag (with SHA256) in helmrelease.yaml
2. Commit and push
3. Flux reconciles automatically
4. Monitor: `flux get helmrelease <name> -n <namespace> --watch`

### Rotating Secrets

1. Update value in Doppler
2. ExternalSecrets syncs automatically (refresh interval)
3. Reloader restarts pods if annotation present
4. Manual: `kubectl rollout restart deployment <name> -n <namespace>`

## Important File Paths

**Core Configuration:**

- [/home/rtrox/home-ops/Taskfile.yaml](/home/rtrox/home-ops/Taskfile.yaml) - Main task orchestration
- [/home/rtrox/home-ops/.sops.yaml](/home/rtrox/home-ops/.sops.yaml) - SOPS encryption rules
- [/home/rtrox/home-ops/.mise.toml](/home/rtrox/home-ops/.mise.toml) - Development tools

**Chongus Cluster:**

- [/home/rtrox/home-ops/clusters/chongus/talos/talconfig.yaml](/home/rtrox/home-ops/clusters/chongus/talos/talconfig.yaml) - Talos config
- [/home/rtrox/home-ops/clusters/chongus/flux/cluster/cluster.yaml](/home/rtrox/home-ops/clusters/chongus/flux/cluster/cluster.yaml) - Flux root
- [/home/rtrox/home-ops/clusters/chongus/bootstrap/helmfile.d/](/home/rtrox/home-ops/clusters/chongus/bootstrap/helmfile.d/) - Bootstrap configs
- [/home/rtrox/home-ops/cluster-apps/chongus/](/home/rtrox/home-ops/cluster-apps/chongus/) - Applications

**Components:**

- [/home/rtrox/home-ops/cluster-apps/components/namespace/](/home/rtrox/home-ops/cluster-apps/components/namespace/) - Basic namespace
- [/home/rtrox/home-ops/cluster-apps/components/privileged-namespace/](/home/rtrox/home-ops/cluster-apps/components/privileged-namespace/) - Privileged
- [/home/rtrox/home-ops/cluster-apps/components/volsync/](/home/rtrox/home-ops/cluster-apps/components/volsync/) - Backup integration
- [/home/rtrox/home-ops/cluster-apps/components/flux/alerts/](/home/rtrox/home-ops/cluster-apps/components/flux/alerts/) - Error alerts

**Bootstrap:**

- [/home/rtrox/home-ops/.taskfiles/k8s-bootstrap/Taskfile.yaml](/home/rtrox/home-ops/.taskfiles/k8s-bootstrap/Taskfile.yaml) - Bootstrap tasks
- [/home/rtrox/home-ops/.taskfiles/talos/Taskfile.yaml](/home/rtrox/home-ops/.taskfiles/talos/Taskfile.yaml) - Talos tasks

## Naming Conventions

- **Applications**: kebab-case (paperless-ngx, kube-prometheus-stack)
- **Namespaces**: single-word lowercase (default, observability, system)
- **Variables**: SCREAMING_SNAKE_CASE (APP, VOLSYNC_CAPACITY)
- **Labels**: Kubernetes standard (app.kubernetes.io/name)
- **Files**: lowercase with extension (helmrelease.yaml, ks.yaml)
- **Flux Kustomization**: `ks.yaml`
- **Kustomize Kustomization**: `kustomization.yaml`

## Security Considerations

- **Non-root containers**: Default security context for all apps
- **Read-only filesystems**: Where possible
- **Pod Security Standards**: privileged-namespace component for exceptions
- **Network policies**: Handled by Cilium (default deny not currently implemented)
- **Secret encryption**: SOPS with age keys
- **Image verification**: SHA256 pinning required
- **Resource limits**: All containers must have memory limits
- **RBAC**: Minimal permissions via HelmRelease serviceAccount

## Resource Quotas and Limits

**Flux Controllers:**

- kustomize-controller: 2Gi memory limit
- helm-controller: 2Gi memory limit
- source-controller: 2Gi memory limit

**Infrastructure:**

- Prometheus: 100m CPU request, 2Gi memory limit
- Alertmanager: No specific limits
- Grafana: Defined per deployment
- Rook-Ceph: No limits (system-critical)

**Applications:**

- All containers must define memory limits
- CPU requests recommended, limits optional
- Storage: Defined per PVC in app HelmRelease

## Development Tools

Managed via `.mise.toml`:

- talhelper 3.0.21
- cilium-cli 0.18.3
- flux2 2.5.1
- helm 3.17.3
- helmfile 0.171.0
- kubectl 1.32.3
- kustomize 5.6.0
- sops 3.10.2
- task 3.42.1
- age 1.2.1
- yq 4.45.1
- jq 1.7.1

## Key Principles

1. **Always follow Chongus patterns** for new work
2. **Use ExternalSecrets + Doppler** for all secrets
3. **Pin images to SHA256** for reproducibility
4. **One OCIRepository per app** for isolation
5. **Components over copy-paste** for reusability
6. **Gateway API over Ingress** for HTTP routing (prefer envoy-internal)
7. **Flux Kustomization dependencies** for ordering
8. **Volsync for stateful apps** with dual-backend
9. **Resource limits** on all containers
10. **Test with flux-local** before committing
11. **Prefer Helm charts** over raw manifests for easier management
12. **Keep CLAUDE.md updated** with each significant change to patterns or architecture
