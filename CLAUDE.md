# Home-Ops Repository Context

> **Important**: This document should be kept up-to-date with each significant architectural change to ensure AI agents and contributors have accurate context.

## Overview

This repository implements a GitOps-managed Kubernetes infrastructure using FluxCD, running two clusters: Chongus (primary, modern pattern) and Bitty (secondary, being phased out). The infrastructure is built on Talos Linux with a focus on automation, high availability, and disaster recovery.

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

## Table of Contents

1. [Key Principles](#key-principles)
2. [Cluster Specifications](#cluster-specifications)
3. [Repository Structure](#repository-structure)
4. [Application Structure](#application-structure)
5. [Technology Stack](#technology-stack)
6. [Common Patterns](#common-patterns)
7. [Anti-Patterns](#anti-patterns)
8. [Network Architecture](#network-architecture)
9. [Naming Conventions](#naming-conventions)
10. [Common Operations](#common-operations)

**Additional Documentation:**

- [Hardware Specifications](docs/HARDWARE.md)
- [Working with Reference Implementations](docs/REFERENCE_IMPLEMENTATIONS.md) *(Phase 2)*
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) *(Phase 2)*
- [Bootstrap & Recovery](docs/BOOTSTRAP.md) *(Phase 2)*

## Cluster Specifications

### Chongus Cluster (Primary - Follow This Pattern)

**Summary:** 3x Dell R730 nodes with NVIDIA GPUs, primary production cluster. [Full hardware details](docs/HARDWARE.md)

**Critical Configuration:**

- **Kubernetes**: v1.33.0 on Talos v1.10.6
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12
- **Load Balancer Pool**: 172.22.12.0/24
  - 172.22.12.1: envoy-internal (default, local network)
  - 172.22.12.2: envoy-external (internet via Cloudflare)

**Storage Classes:**

- `ceph-block` - Default for persistent data (Rook-Ceph, 3x replication)
- `openebs-hostpath` - Local cache/temp storage (Volsync operations)
- NFS mounts: `nas.rtrox.io:/mnt/rusty/media/*`

**Key Capabilities:**

- GPU support (NVIDIA with nvidia-container-toolkit)
- Cilium CNI with Gateway API
- External-DNS (Cloudflare)

### Bitty Cluster (Secondary - Being Phased Out)

**Summary:** 3x Intel NUC nodes with QuickSync iGPU, secondary cluster for smaller workloads.

- Kubernetes v1.33.0 on Talos v1.10.1
- IP Range: 172.30.21.1-3
- Use for: QuickSync video transcoding only
- **Do not deploy new applications to Bitty** - migrate to Chongus

## Repository Structure

### Understanding Namespace Directories

Directories immediately under `cluster-apps/chongus/` or `cluster-apps/bitty/` are **Kubernetes namespace directories**, NOT application directories. Each namespace directory:

- Represents a single Kubernetes namespace
- Contains a `kustomization.yaml` that includes namespace components and lists all apps
- Contains subdirectories for applications deployed to that namespace

### Directory Hierarchy

```text
cluster-apps/chongus/
├── [namespace-name]/              # ← NAMESPACE DIRECTORY (e.g., "default", "system", "observability")
│   ├── kustomization.yaml         # Namespace config + app list
│   ├── [app-1]/                   # Application directory
│   │   ├── app/                   # HelmRelease + configs
│   │   └── ks.yaml                # Flux Kustomization
│   └── [app-2]/                   # Another app in same namespace
│       └── ...
```

### Full Repository Structure

```text
/home/rtrox/home-ops/
├── ansible/                    # Non-k8s machines (Raspberry Pis)
│   └── roles/
├── cluster-apps/               # Main FluxCD source (ACTIVE)
│   ├── base/                   # Shared across clusters
│   │   └── [app]/app/         # Cross-cluster applications
│   ├── chongus/               # Chongus-specific apps (NEW PATTERN)
│   │   ├── [namespace]/       # ← NAMESPACE DIRECTORY (K8s namespace)
│   │   │   ├── kustomization.yaml  # Namespace config
│   │   │   └── [app]/              # App in this namespace
│   │   │       ├── app/            # HelmRelease + configs
│   │   │       └── ks.yaml         # Flux Kustomization
│   │   ├── default/           # "default" namespace
│   │   ├── system/            # "system" namespace (privileged)
│   │   ├── observability/     # "observability" namespace
│   │   └── actions-runner-system/  # "actions-runner-system" namespace
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

### Namespace Directory Structure

Every namespace directory under `cluster-apps/chongus/[namespace]/` contains:

1. **`kustomization.yaml`** - Namespace configuration listing all apps
2. **`[app-name]/`** - One directory per application

### Application Directory Structure

Every application follows this standard structure within its namespace directory:

```text
cluster-apps/chongus/[namespace]/          ← Namespace directory (e.g., "default", "observability")
├── kustomization.yaml                      ← Namespace config + app list
└── [appname]/                              ← Application directory
    ├── app/                                ← Application manifests
    │   ├── helmrelease.yaml                # Helm chart deployment
    │   ├── ocirepository.yaml              # Per-app chart source
    │   ├── externalsecret.yaml             # Doppler secret integration (optional)
    │   ├── kustomization.yaml              # Kustomize resources list
    │   └── config/                         # ConfigMap sources (optional)
    │       └── [config-files]
    └── ks.yaml                             ← Flux Kustomization (orchestrator)
```

**Key Files:**

- **Namespace `kustomization.yaml`**: Lists all apps, includes namespace components
- **App `ks.yaml`**: `kustomize.toolkit.fluxcd.io/v1` Kustomization (Flux resource)
- **App `app/kustomization.yaml`**: `kustomize.config.k8s.io/v1beta1` Kustomization (Kustomize resource list)
- Components included at namespace level or via `components:` field in `ks.yaml`

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
- **Preferred Pattern**: Single Doppler secret key per app with JSON structure
  - Extract entire JSON object using `dataFrom.extract`
  - Use `target.template` to expand individual values
  - Example: `BOOKLORE` key in Doppler contains `{"mariadb_password": "...", "mariadb_root_password": "..."}`
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

**Common Charts:**

- **bjw-s app-template**: `oci://ghcr.io/bjw-s-labs/helm/app-template` - Modern, flexible chart for common app patterns (supports init containers, sidecars, persistence, etc.)

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

### Flux Kustomization Pattern (ks.yaml)

```yaml
# In ks.yaml - Flux Kustomization (NOT Kustomize kustomization.yaml)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app app-name
  namespace: &namespace default
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../components/volsync  # Relative to path field, not ks.yaml location
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
    - name: external-secrets-store-doppler
      namespace: external-secrets
  interval: 1h
  retryInterval: 2m
  timeout: 5m
  path: ./cluster-apps/chongus/namespace/app-name/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system        # ALWAYS use flux-system
    namespace: flux-system   # ALWAYS include namespace
  targetNamespace: *namespace
  wait: false
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: 10Gi
      VOLSYNC_CLAIM: *app
```

**Critical Details:**

- **sourceRef.name**: ALWAYS `flux-system` (not `home-ops` or other names)
- **sourceRef.namespace**: ALWAYS `flux-system`
- **Component paths**: Relative to `spec.path` field (e.g., `../../../../components/volsync`)
- **namespace anchor**: Use `&namespace` and reference with `*namespace`
- **app anchor**: Use `&app` for reuse in metadata, labels, and substitutions

### Volsync Backup Pattern

```yaml
# In ks.yaml - postBuild section only
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
14. **Wrong GitRepository name** - ALWAYS use `flux-system` in sourceRef, never `home-ops` or other names

## Working with External References

When implementing apps from external repos (kubesearch.dev, bjw-s-labs/home-ops, etc.):

1. **Extract** patterns (images, probes, volumes) exactly as-is
2. **Adapt** to Chongus standards (nas.rtrox.io, Doppler secrets, envoy-internal, flux-system)
3. **Validate** with flux-local test before committing

See [full guide](docs/REFERENCE_IMPLEMENTATIONS.md) for detailed workflow and common mistakes.

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


## Troubleshooting

See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for detailed debugging procedures.

**Home-ops specific:**
- **Doppler**: Verify token with `kubectl get secret doppler-token -n external-secrets`
- **Volsync**: Check replication status with `kubectl get replicationsource -A`
- **Ceph**: Health check via `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status`

## Bootstrap & Recovery

See [Bootstrap Guide](docs/BOOTSTRAP.md) for detailed procedures.

**Quick bootstrap:**
```bash
task talos:generate-clusterconfig
task talos:apply-clusterconfig
task k8s-bootstrap:talos-cluster
task k8s-bootstrap:apps
```
## Common Operations

### Adding a New Application (Chongus Pattern)

#### First: Determine the Namespace

Before adding an application, decide which Kubernetes namespace it belongs in:

- **Use existing namespace** if the app fits the category (e.g., `observability`, `network`, `database`)
- **Create new namespace** only if:
  - The app represents a new functional category
  - The app requires different security/privilege levels
  - The app is logically isolated from existing namespaces

#### To add an app to an EXISTING namespace

1. Navigate to: `cluster-apps/chongus/[namespace]/`
2. Create app directory: `cluster-apps/chongus/[namespace]/[app-name]/`
3. Create `app/` subdirectory
4. Add `helmrelease.yaml` with chartRef to OCIRepository
5. Add `ocirepository.yaml` for chart source
6. Add `externalsecret.yaml` if secrets needed
7. Add `app/kustomization.yaml` listing resources
8. Add `ks.yaml` Flux Kustomization with dependencies
9. Add `./[app-name]/ks.yaml` to namespace `kustomization.yaml` resources list
10. Commit and push - Flux will reconcile

#### To create a NEW namespace directory

1. Create directory: `cluster-apps/chongus/[namespace-name]/`
2. Create `kustomization.yaml` with:
   - `namespace: [namespace-name]`
   - `components:` - Use `../../components/namespace` (standard) or `../../components/privileged-namespace` (if elevated permissions needed)
   - `resources: []` - Will list app ks.yaml files
3. Follow steps above to add first app
4. Commit and push - Flux will auto-discover the new namespace

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

## Development Tools

All development tools are managed via [.mise.toml](.mise.toml). Run `mise install` to set up the environment.

**Critical requirement:** All application containers must define memory limits.
