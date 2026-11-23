# Home-Ops Repository Context

> **Important**: This document should be kept up-to-date with each significant architectural change to ensure AI agents and contributors have accurate context.

## Overview

This repository implements a GitOps-managed Kubernetes infrastructure using FluxCD, running one cluster: Mini (primary, modern pattern). The infrastructure is built on Talos Linux with a focus on automation, high availability, and disaster recovery.

> Chongus (the original primary cluster) was decommissioned and its config removed from this repo. Its `actions-runner-system` namespace was deliberately not migrated to Mini -- not currently needed, can be re-added later if that changes. Full history is in git. Its `database` namespace (CloudNativePG, redis) *has* been re-added to Mini, rebuilt from that same git history -- see [CloudNativePG & Valkey (`database` namespace)](#cloudnativepg--valkey-database-namespace) below.

> Bitty (the secondary cluster) was decommissioned and its config archived, not deleted, at `.archive/bitty/` (2026-11-04). A new Bitty is planned; the archive is kept as reference for that rebuild, since it holds hardware details like the Talos install-disk selectors. Nothing in `.archive/` is deployed, and Renovate doesn't track it.

## Key Principles

1. **Always follow Mini's patterns** for new work
2. **Use ExternalSecrets + Doppler** for all secrets
3. **Pin images to SHA256** for reproducibility
4. **One OCIRepository per app** for isolation
5. **Components over copy-paste** for reusability
6. **Gateway API over Ingress** for HTTP routing (prefer envoy-internal)
7. **Flux Kustomization dependencies** for ordering
8. **Volsync for stateful apps** with dual-backend
9. **Resource limits** on all containers
10. **Test with flate** before committing
11. **Prefer Helm charts** over raw manifests for easier management
12. **Keep CLAUDE.md updated** with each significant change to patterns or architecture

## Infrastructure Migration (in progress)

Terraform is moving from the private `terraform-record` repo into this repo, reorganized by consumer, with internal DNS, Garage storage and a Proxmox-hosted CI runner. The design lives in two docs the repo owner keeps outside the repo: **Home infrastructure: target architecture** and **Home infrastructure: migration plan** (nine phases, 0 to 8, each with tasks and exit checks).

**Current phase:** 2 (Terraform stack moves, from terraform-record into `terraform/stacks/`). Phases 0 and 1 are done. Phase 1 built the R2 backend, the Terramate skeleton, the inventory, the `proxmox` stack, the CI runner with read-only PR plans, and apartment DNS (dns-a1 on Proxmox, dns-a2 in mini). Its Knot spike passed, so the internal zone's primary is Knot, not BIND.

**`terraform/`** holds the new stacks (`terraform/stacks/<name>/`, each with a `stack.tm.hcl`), orchestrated by the open-source Terramate CLI.
- **Generated files:** `terraform/terramate.tm.hcl` generates each stack's `_backend.tf`: the S3 backend on the R2 bucket `tofu-state`, keyed by stack path, with `use_lockfile` and enforced state encryption. Never edit a generated file (they start with `// TERRAMATE: GENERATED`); change `terramate.tm.hcl` and run `task tf:generate`. A pre-commit hook and the `terraform-check` CI job fail on stale generated files.
- **Credentials:** `task tf:init|plan|apply STACK=<name>` reads the R2 credentials and `TOFU_STATE_PASSPHRASE` from Doppler `tf-at-home/prd` into the environment. Those tasks use the read-write R2 token, so they're the owner's to run; agents may run `tofu validate` with `init -backend=false`.
- **Provider credentials come from the environment, never a `doppler_secrets` data source** (a data source is stored in state, so it would put a whole Doppler config in every stack's state, and CI's plan job can decrypt state). Terramate generates, per stack, `_provider_env.json` (`[{env, project, key}]`) from the stack's `providers`, `doppler_writes` and `secret_vars` globals plus the `provider_env` table in `terramate.tm.hcl`. `task tf:*` exports those variables from `tf-at-home/prd` and `hosts-at-home/prd`, and CI's `tf_export_provider_env` (`tf-ci.sh`) does the same from the `ci` configs (plans, drift) or `ci-apply` (applies), per stack, masked. Providers read their standard variables (`CLOUDFLARE_API_TOKEN`, `PROXMOX_VE_API_TOKEN`). Any other secret a stack needs is a sensitive variable: add it to the stack's `secret_vars` (`{ name = { project, key } }`), which generates `variable "<name>"` and exports `TF_VAR_<name>`; unless the stack is `laptop-only`, the key must exist in `tf-at-home/ci` (and `ci-apply`) too; laptop-only stacks never run in CI, so keep their keys out of it. A new provider adds its entry to `provider_env`. The CI tokens only read the `ci` configs.
- **Laptop-only stacks have their own state passphrase:** for a stack tagged `laptop-only` (e.g. `foundation`), `task tf:*` sets `TF_VAR_state_passphrase` from `TOFU_STATE_PASSPHRASE_LAPTOP` instead, and stops if it's missing, never falling back. CI holds the shared passphrase and a read-only R2 token that reads every key, so it can download those states but never decrypt them. The owner keeps a Bitwarden copy, since losing it makes the state unreadable.
- **CI plans:** `.github/workflows/terraform-plan.yaml` plans changed stacks on the self-hosted runner with read-only credentials (Doppler `ci` configs, `-lock=false`) and posts only resource headers and counts. A stack lists addresses CI can't read in `ci-plan-exclude.txt` (proxmox: the ACME plugin, which needs `Sys.Modify`); plan those from the laptop.
- **CI and stack tags:** `terraform-plan` (PRs), `terraform-apply` (merge to main) and `terraform-drift` (nightly, 03:30 Pacific) share `.github/scripts/tf-ci.sh`. Stack tags in `stack.tm.hcl`: `laptop-only` (CI never plans, applies or drift-checks it), `ci-apply` (opt-in to apply-on-merge), `gated` (with `ci-apply`: approval in the `tofu-apply-gated` Environment, else `tofu-apply`). Apply jobs read Doppler `tf-at-home/ci-apply` with the Environment secret `CI_DOPPLER_TF_APPLY`; the key names are in the `terraform-apply.yaml` header. Nothing uploads or prints a plan.
- **Versions:** provider versions live in each stack's own `versions.tf`, so Renovate's terraform manager can bump them and their committed lock files. Terramate generates the repeated provider *configuration*, not the version pins.

**Lead sessions start with the migration plan doc's Handoff tab**: current state, decisions made, facts already gathered. Read and update it with the Claude Docs tools, from any machine. It replaces the local `.claude/migration/HANDOFF.md` earlier sessions used.

### Agents

Agent definitions live in `.claude/agents/`. The lead (the main session) breaks a phase into PR-sized tasks and delegates:

| Agent | Model | Effort | Use for |
| --- | --- | --- | --- |
| Lead (main session) | Opus 5.5 | high | Planning a phase, delegating, checking exit criteria, keeping the docs current |
| `recon` | Haiku 5.5 | low | Read-only extraction and comparison |
| `iac-implementer` | Sonnet 5.5 | medium | One well-specified task per worktree, validated, ready for a PR |
| `state-mover` | Opus 5.5 | high | Phase 2 stack moves and the phase 0 pocket-id reconcile |
| `plan-reviewer` | Opus 5.5 | high | Independent review of every high-risk PR: Terraform plans, state or imports, credentials and keys, Doppler writes, anything that can destroy |
| `plan-reviewer`, low-risk tier | Sonnet 5.5 | medium | Independent review of changes a revert fully undoes: Flux/Kubernetes config, CronJobs, docs |
| `docs-keeper` | Haiku 5.5 | low | Documentation after a change lands |

These model and effort levels are deliberate; the lead may set them explicitly when delegating. `plan-reviewer`'s file defaults to Opus, so the lead passes Sonnet explicitly for the low-risk tier; when in doubt, use Opus. Escalation: an implementer task that fails validation twice moves to Opus 5.5; an uncertain review on a high-risk change gets a second, independent Opus 5.5 review.

### Rules

- **Agents never apply.** No `tofu apply`, imports or state edits, Doppler writes, router changes, `kubectl` mutations, Talos applies or non-check Ansible runs. `.claude/settings.json` denies those commands, but that's a guard rail, not a sandbox: the real boundary is that agents hold read-only credentials. Applies run by hand from the laptop, or in CI for stacks tagged `ci-apply`: behind owner approval in `tofu-apply-gated` for `gated` stacks, with no approval in `tofu-apply` for the rest.
- **Agents may merge** a PR (`gh pr merge --squash`) once its required CI checks pass and an independent review approved it, with every BLOCK resolved. A merge into `cluster-apps/` or `clusters/` is an apply (Flux reconciles it), so only easily reverted changes are merged without asking. Ask the owner first for anything that destroys, migrates data, touches credentials or networking (DNS, LoadBalancers, firewall), or can't be undone by a revert. Merging Terraform or Ansible code applies nothing by itself; the owner still runs those applies, so state the next apply step after merging. **Exception: once any stack is tagged `ci-apply`, a merge that triggers `terraform-apply` is an apply of every `ci-apply` stack** (it plans all of them on each push, and `tofu-apply` has no reviewers). That covers anything under `terraform/**` or `inventory/**`, even a README, plus the workflow and `.github/scripts/tf-ci.sh`. Agents always ask the owner before merging such a PR, whatever the change.
- **Reviews are independent.** The reviewer gets the diff and the plan, never the implementer's reasoning. Mechanical checks (no destroys, sensitive PII, `doppler_secret` values unchanged) also run in CI regardless.
- **One worktree per implementer**, and at most two implementer tracks at once, since every apply waits on a human.
- **Never print secret values.** Pulled state and exports stay in the session scratchpad and are deleted after use.
- **The repo owner does the learning-heavy parts by hand**: the Terramate skeleton, the first stack, and the Knot/external-dns spike, with the lead as pair and reviewer.

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

### Mini Cluster (Primary - Follow This Pattern)

**Summary:** 3x Minisforum MS-A2 nodes (AMD Ryzen, dual NVMe: 2TB boot + 4TB storage), primary production cluster. [Full hardware details](docs/HARDWARE.md)

**Critical Configuration:**

- **Kubernetes**: v1.36.4 on Talos v1.14.5 (source of truth: `kubernetesVersion`/`talosVersion` in `clusters/mini/talos/topf.yaml`; tuppr performs the upgrades)
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12
- **IP Range**: 172.21.31.1-3
- **Load Balancer Pool**: 172.19.32.0/24 (Cilium LBIPAM, must stay distinct from any other cluster's pool since these networks are routable to each other)
  - 172.19.32.1: envoy-internal (default, local network)
  - 172.19.32.2: envoy-external (internet via a dedicated `cloudflared` Cloudflare Tunnel, external hostname `min-ext.rtrox.io`). Its tunnel ingress covers `rtrox.io`/`*.rtrox.io` -- this won't collide with another cluster's tunnel, since each hostname's DNS record (managed per-HTTPRoute by external-dns) only points at whichever cluster's tunnel is actually serving it.
  - 172.19.32.3-.7: assigned automatically (lowest free address) to LoadBalancer Services that don't request one: scrypted-nvr, qbittorrent-gluetun, owncast-rtmp, minecraft-vanilla, graphite-exporter. Not pinned, so they can change if a Service is recreated
  - 172.19.32.200: loki-lan, Loki's push endpoint for Alloy on the Ansible DNS hosts (source-restricted to ns1/ns2)
  - **Picking a fixed address:** `kubectl get svc -A | grep LoadBalancer` shows what's actually taken; grepping the repo for `lbipam.cilium.io/ips` misses the automatic ones. Pin new addresses high in the pool (e.g. .200+) so they can't collide with automatic ones

**Storage Classes:**

- `ceph-block` - Default for persistent data (Rook-Ceph, 3x replication, all 3 nodes' 4TB storage NVMes via `useAllDevices: true`)
- `openebs-hostpath` - Local cache/temp storage (Volsync operations)
- NFS mounts: `nas.rtrox.io:/mnt/rusty/media/*`
- `cephClusterSpec.security.cephx` is pinned to the `aes` key type (not the v1.20 default `aes256k`), since Talos v1.14.5 still ships kernel 6.18, below the 7.0+ aes256k requires
- Rook-Ceph chart/image versions are never auto-merged by Renovate (see `.github/renovate/autoMerge.json5`) -- check the Rook/Ceph support matrix before merging one, same rule for every cluster

**Key Capabilities:**

- GPU support: every node has the AMD `amdgpu` iGPU (`siderolabs/amdgpu` + `siderolabs/amd-ucode`, applied in the cluster-wide `schematic.yaml`, referenced by `schematicId` in `clusters/mini/talos/topf.yaml`). **node03 additionally has an NVIDIA RTX 3050** (`siderolabs/nonfree-kmod-nvidia-production` + `siderolabs/nvidia-container-toolkit-production` + `nvidia`/`nvidia_uvm`/`nvidia_drm`/`nvidia_modeset` kernel modules), applied as a **node-level override** on node03 only: `schematicId: "@schematic-node03.yaml"` on its entry in `clusters/mini/talos/topf.yaml`, plus the kernel modules in `node/node03.mini.rtrox.io/`. A node-level schematic *replaces* (does not merge with) the cluster one, so `schematic-node03.yaml` repeats the full AMD extension list alongside the NVIDIA additions. **If more GPUs are added to other mini nodes, give that node its own `schematicId` and `node/<host>/` patch** — it won't inherit from node03 or from the cluster schematic automatically. `nvidia-device-plugin` (`cluster-apps/mini/system/nvidia-device-plugin`) self-targets node03 via the NFD label `feature.node.kubernetes.io/pci-0300_10de.present: "true"`, so no manual node pinning is needed there.
- Talos machine config is managed with [topf](https://github.com/postfinance/topf) (talhelper was archived upstream on 2026-08-26, so it can't support Talos 1.14): `clusters/mini/talos/topf.yaml` (nodes, versions, schematics, secureboot) plus strategic-merge patches in `all/`, `control-plane/`, `node/<host>/` and secrets in `secrets.sops.yaml`. `task talos:generate-clusterconfig` renders, `task talos:apply-clusterconfig DRY_RUN=true` previews (must say "no changes to apply" on every node). tuppr stays the only thing that upgrades Talos. No JSON patches (topf rejects them); use `$patch: delete`. Talos 1.14 config uses the new documents (`KubeNodeConfig`, `ResolverConfig`, `KubeletConfig`, `KubeAPIServerConfig`, ...), not the legacy `.machine.kubelet`/`.cluster.apiServer` fields; Talos rejects a config that sets both, so run `task talos:validate-clusterconfig` after any change. `topf.yaml`'s `talosVersion` must match what the nodes run when you `apply`: bump it with the tuppr upgrade, and apply only once the nodes have finished upgrading.
- Install disk: boot disk selected via the `UnattendedInstallConfig` CEL selector `disk.size < 3u * TB` (`clusters/mini/talos/all/02-install.yaml`) (picks the 2TB NVMe over the 4TB storage NVMe, which is reserved for Rook-Ceph)
- Cilium CNI with Gateway API
- External-DNS (Cloudflare)
- CloudNativePG and Valkey are live (`database` namespace). Observability (kube-prometheus-stack/Grafana/Loki/Alloy) is live.

### Bitty Cluster (Decommissioned - Archived)

**Summary:** The previous Bitty was 3x Intel NUC nodes with QuickSync iGPU. It no longer exists; a new Bitty is planned.

- Config archived at `.archive/bitty/` (`clusters/` and `cluster-apps/`, see its [README](.archive/bitty/README.md)). Reference only: nothing there is deployed, and Renovate doesn't track it, so its versions go stale
- Hardware facts: [docs/HARDWARE.md](docs/HARDWARE.md) and `.archive/bitty/clusters/talos/talconfig.yaml` (old talhelper format)
- **Do not deploy applications to Bitty** - deploy to Mini
- `flux`/`talos`/`k8s-bootstrap` tasks stay generic on `CLUSTER_NAME`, so a new Bitty built under `clusters/bitty/` works without rewriting them

## Repository Structure

### Understanding Namespace Directories

Directories immediately under `cluster-apps/mini/` are **Kubernetes namespace directories**, NOT application directories. Each namespace directory:

- Represents a single Kubernetes namespace
- Contains a `kustomization.yaml` that includes namespace components and lists all apps
- Contains subdirectories for applications deployed to that namespace

### Directory Hierarchy

```text
cluster-apps/mini/
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
├── .archive/                   # Archived config, not deployed, ignored by Renovate
│   └── bitty/                 # Decommissioned Bitty cluster (clusters/ + cluster-apps/)
├── ansible/                    # Non-k8s machines (Raspberry Pis), see ansible/README.md
│   └── roles/
├── cluster-apps/               # Main FluxCD source (ACTIVE)
│   ├── base/                   # Shared across clusters
│   │   └── [app]/app/         # Cross-cluster applications
│   ├── mini/                  # Mini-specific apps (NEW PATTERN)
│   │   ├── [namespace]/       # ← NAMESPACE DIRECTORY (K8s namespace)
│   │   │   ├── kustomization.yaml  # Namespace config
│   │   │   └── [app]/              # App in this namespace
│   │   │       ├── app/            # HelmRelease + configs
│   │   │       └── ks.yaml         # Flux Kustomization
│   │   ├── default/           # "default" namespace
│   │   ├── system/            # "system" namespace (privileged)
│   │   └── observability/     # "observability" namespace
│   └── components/            # Reusable Kustomize components
│       ├── flux/alerts/       # Flux error notifications
│       ├── namespace/         # Basic namespace template
│       ├── privileged-namespace/  # Privileged workload namespace
│       └── volsync/           # PVC + backup templates
├── clusters/                   # Cluster definitions & bootstrap
│   └── mini/
│       ├── bootstrap/         # Helmfile-based bootstrap
│       │   ├── helmfile.d/    # 00-crds.yaml, 01-apps.yaml
│       │   ├── resources/
│       │   └── templates/
│       ├── flux/              # Flux Kustomizations
│       │   └── cluster/
│       └── talos/             # Talos configuration
│           └── clusterconfig/
└── .taskfiles/                # Operational automation
    ├── k8s-bootstrap/
    ├── sops/
    └── talos/
```

## Application Structure

### Namespace Directory Structure

Every namespace directory under `cluster-apps/mini/[namespace]/` contains:

1. **`kustomization.yaml`** - Namespace configuration listing all apps
2. **`[app-name]/`** - One directory per application

### Application Directory Structure

Every application follows this standard structure within its namespace directory:

```text
cluster-apps/mini/[namespace]/              ← Namespace directory (e.g., "default", "observability")
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

### New Pattern (Mini - FOLLOW THIS)

**HTTP Routing:**

- Gateway API with Envoy Gateway
- HTTPRoute resources for ingress
- Two gateways:
  - **`envoy-external` (172.19.32.2)**: Connected to Cloudflare Tunnel, internet-accessible
  - **`envoy-internal` (172.19.32.1)**: Local network only (accessible via Tailscale)
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
  path: ./cluster-apps/mini/namespace/app-name/app
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

### CloudNativePG & Valkey (`database` namespace)

Shared, cluster-wide database infra for apps that need Postgres or a Redis-compatible cache, in `cluster-apps/mini/database/`. Rebuilt from Chongus's git history (see the note in Overview), adjusted for Mini's Doppler/MinIO conventions.

- **CloudNativePG operator** (`cloudnative-pg/app/`): installed via its own OCI Helm chart (`oci://ghcr.io/cloudnative-pg/charts/cloudnative-pg`), `crds.create: true`. Its ExternalSecret (`cloudnative-pg-secret`) merges two Doppler JSON secrets via `dataFrom.extract`: the Postgres superuser creds (`CNPG_ROOT_CREDENTIALS` -- `username`/`password`) and the WAL/base-backup MinIO bucket (`CNPG_MINIO_BUCKET`, same `endpoint`/`bucket`/`application_key_id`/`application_key` shape as the volsync/thanos MinIO secrets).
- **Barman Cloud plugin** (`cloudnative-pg-barman-plugin/`, HelmRelease `plugin-barman-cloud`): backups and WAL archiving go through the CNPG-I Barman Cloud plugin, not CNPG's in-tree `spec.backup.barmanObjectStore` (deprecated, removed in CNPG 1.32.0). It must run in the operator's namespace (`database`), and its chart creates a self-signed cert-manager `Issuer` + client/server `Certificate`s for the operator<->plugin mTLS, so it depends on both `cloudnative-pg` and `cert-manager`. It injects a `plugin-barman-cloud` sidecar into every instance pod; that sidecar's resources come from the ObjectStore's `instanceSidecarConfiguration`, not the HelmRelease.
- **One shared `Cluster`** (`cloudnative-pg/cluster/cluster.yaml`, named `postgres17`): 3-node HA, backs up to MinIO via the plugin (`spec.plugins` -> ObjectStore `minio` in `cloudnative-pg/cluster/objectstore.yaml`, which holds the bucket, bzip2 compression and the 14-day `retentionPolicy`; `@daily` + immediate `ScheduledBackup` with `method: plugin`). The ObjectStore uses `${ENDPOINT}`/`${BUCKET}` substituted from `cloudnative-pg-secret` via the `cloudnative-pg-cluster` Kustomization's `postBuild.substituteFrom` -- never hardcode the MinIO endpoint/bucket in the manifest. `serverName` goes in the Cluster's plugin `parameters`, never in the ObjectStore (its CRD rejects it). Backup metrics are `barman_cloud_cloudnative_pg_io_*` (the `cnpg_collector_*backup*`/`first_recoverability_point` ones are the deprecated in-tree names), scraped by the Cluster's existing PodMonitor.
- **Per-app database**: each consuming app gets (a) an entry in the shared Cluster's `spec.managed.roles` (password via a `passwordSecret`, *not* auto-generated -- see below) and (b) its own `postgresql.cnpg.io/v1 Database` CR pointing at `postgres17`. Add both directly in `cloudnative-pg/cluster/` (e.g. `database-<app>.yaml`) rather than creating a whole new Cluster per app.
- **Why not CNPG's auto-generated app secret**: the Cluster lives in `database`, but consuming apps live in their own namespace (e.g. `default`), and Kubernetes secrets can't be referenced cross-namespace. So the role's password is *not* left to CNPG to generate -- it's sourced from one Doppler secret (e.g. `SURE` with a `postgres_password` key) via **two** ExternalSecrets: one in `database` (feeding `managed.roles[].passwordSecret`) and one in the app's own namespace (feeding the app's env). `DB_HOST`/`DB_PORT`/`POSTGRES_DB`/`POSTGRES_USER` aren't secret -- set them as plain values (`<cluster>-rw.database.svc.cluster.local`, role/db name) directly in the app's HelmRelease.
- **Valkey** (`valkey/app/`): single unauthenticated instance, no persistence -- a pure cache/job-queue store (mirrors the existing `paperless-redis` pattern, swapped to the `valkey/valkey` image). Reachable cluster-wide at `valkey.database.svc.cluster.local:6379`; since there's no auth, no cross-namespace secret problem.
- **App storage that needs multi-pod access** (e.g. a web + worker controller pair both touching uploaded files): don't reach for a `ceph-block` PVC -- it's ReadWriteOnce and can't be mounted by both pods reliably. Point the app at a MinIO bucket instead (`GENERIC_S3_*`-style env vars, or equivalent) via its own dedicated MinIO bucket secret, same shape as the CNPG one above.

## Anti-Patterns (DO NOT USE)

1. **Centralized HelmRepository** - Each app should have its own OCIRepository
2. **SOPS for application secrets** - Use ExternalSecrets + Doppler instead
3. **postBuild substitution from SOPS** - Use ExternalSecrets or direct values
4. **Direct manifest references** - Use components for reusable patterns
5. **Shell scripts for automation** - Use Taskfiles instead
6. **Ingress resources** - Use Gateway API HTTPRoute
7. **Storing secrets in Git** - Even encrypted, prefer ExternalSecrets
8. **Mutable image tags** - Always pin to SHA256 digest
9. **Missing resource limits** - All containers must have memory limits
10. **Raw manifests over Helm charts** - Prefer Helm charts for easier Flux management (not a hard rule, but best practice)
11. **Velero for backups** - Use Volsync instead (Velero is legacy/deprecated)
12. **envoy-external for internal apps** - Prefer envoy-internal unless internet access is explicitly needed
13. **Wrong GitRepository name** - ALWAYS use `flux-system` in sourceRef, never `home-ops` or other names

## Working with External References

When implementing apps from external repos (kubesearch.dev, bjw-s-labs/home-ops, etc.):

1. **Extract** patterns (images, probes, volumes) exactly as-is
2. **Adapt** to Mini standards (nas.rtrox.io, Doppler secrets, envoy-internal, flux-system)
3. **Validate** with flate test before committing

See [full guide](docs/REFERENCE_IMPLEMENTATIONS.md) for detailed workflow and common mistakes.

## Backup and Disaster Recovery

### Volsync Strategy (PRIMARY MECHANISM)

- **Dual-backend**: B2 (daily) + MinIO (hourly)
- **Cache storage**: openebs-hostpath (4Gi per app)
- **Source storage**: ceph-block with snapshots
- **Restoration**: Manual trigger via `restore-once` annotation
- **Status**: Active, preferred backup mechanism for all stateful workloads

### Doppler export

- Weekly CronJob (`security/doppler-export`, Sun 03:00 UTC) downloads every Doppler config with per-config read-only tokens, age-encrypts each to the `.sops.yaml` recipients, and writes the ciphertext to `nas.rtrox.io:/mnt/rusty/backups/doppler/<date>/` and B2 (`doppler/<date>/`), monitored by healthchecks.io

### CloudNative-PG (PostgreSQL)

- **HA**: 3-node cluster with streaming replication
- **Backup**: WAL archiving + base backups to MinIO via the Barman Cloud plugin (ObjectStore `minio`)
- **Retention**: 14 days (`retentionPolicy` on the ObjectStore, not the Cluster)
- **Compression**: bzip2 for data and WAL
- **Schedule**: Daily (@daily) + immediate on creation
- **Off-site copy**: nightly rclone sync (`database/cnpg-offsite`, 02:00 UTC) of the MinIO bucket to B2 `k8s-mini-rtrox-io-cnpg-offsite` (Object Lock 45d, no delete key), monitored by a healthchecks.io cron check; pause the job before phase 4's Garage cutover

### OpenTofu state history

- **State copy**: nightly rclone sync (`terraform/tofu-state-copy`, 04:00 UTC) of the Cloudflare R2 `tofu-state` bucket (encrypted state, read-only token) to the versioned B2 bucket `rtrox-tofu-state-history` (no delete key, so B2 keeps old versions), monitored by a healthchecks.io cron check

## Network Architecture

### Cilium CNI

- **IPAM**: Kubernetes mode (10.244.0.0/16)
- **Routing**: Native routing with auto-direct node routes
- **Load Balancer**: Maglev algorithm, DSR (Direct Server Return) mode
- **KubeProxy**: Replaced by eBPF
- **Features**: BBR bandwidth manager, IPv4 BigTCP, Gateway API support
- **Observability**: Hubble UI and relay enabled

### Load Balancer IP Allocation

- **Pool**: 172.19.32.0/24 (Cilium LBIPAM)
- **External Gateway**: 172.19.32.2 (Cloudflare Tunnel, internet-accessible)
- **Internal Gateway**: 172.19.32.1 (Local network, Tailscale-accessible)

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
- **Dead-man's switch**: the always-firing `Watchdog` alert routes to healthchecks.io about once a minute (`healthchecks-watchdog` receiver, URL from the `alertmanager-healthchecks` ExternalSecret, Doppler `HEALTHCHECKS` / `watchdog_ping_url`). The check (5m period, 5m grace) alerts if pings stop. Created by hand; imported into Terraform in migration phase 7
- **Pushover priority**: firing `severity=critical` alerts, plus `KubePodCrashLooping` and `LastFailedArchiveTime`, send at priority 1. Everything else, including all resolved notices, sends at -1 (quiet). Keep critical for things that need action

## Testing and Validation

### Tool Requirements

All validation tasks require tools managed via [mise](https://mise.jdx.dev/). Ensure tools are installed:

```bash
mise install
```

**Note**: Tasks use `mise exec` to run tools, so mise doesn't need to be activated in your shell.

### Pre-commit Hooks

- Trailing whitespace removal
- End-of-file fixing
- YAML linting (.github/lint/.yamllint.yaml)
- SOPS secret prevention

### GitHub Actions CI

1. **Pre-commit checks**: Run hooks on changed files
2. **YAML lint**: Validate all YAML syntax
3. **Renovate validation**: Check Renovate config
4. **Flate test**: Dry-run all Kustomizations and HelmReleases
5. **Flate diff**: Generate PR diffs for review

**Merge gate**: the "Protect main" ruleset requires a pull request, signed
commits, and two status checks from GitHub Actions:
`flate-mini / Flate successful` and `simple-checks / Lint successful`. Both are
aggregate jobs that always report (they pass when their parts are skipped), so
they cannot hang a PR. Branches need not be up to date with main. The ruleset
has no bypass actors, so a red check blocks everyone: fix it or re-run it. When
renaming or splitting those aggregate jobs, update the ruleset in the same
change or every merge will block on a check name that no longer exists.

### Local Validation

**Quick validation** (recommended for iterative development):

```bash
export CLUSTER_NAME=mini
task flux:test-quick
```

- Validates the Flux Kustomizations (structure, kustomize builds, substitutions)
- Does NOT render Helm charts (avoids registry rate limits)
- Fast: ~7 seconds
- Use this after making changes to verify correctness

**Full validation** (comprehensive, may hit rate limits):

```bash
export CLUSTER_NAME=mini
task flux:test
```

- Validates structure AND renders every HelmRelease's chart (what CI runs)
- May fail with `403: denied` if GHCR rate limits are hit
- Slower: ~15 seconds
- Expect exactly 2 `ConflictingProducers` warnings for the Gateway API
  `safe-upgrades` policy: a known false positive (the Envoy Gateway chart
  skips that object via Helm `lookup` when the cluster already has it, which
  flate cannot evaluate offline). Any other warning is worth a look.
- To avoid rate limits, authenticate with GHCR:

  ```bash
  # Create GitHub PAT with read:packages scope
  echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
  ```

**Other validation tasks**:

```bash
# List all Flux resources
task flux:list CLUSTER_NAME=mini

# Build specific resources
task flux:build CLUSTER_NAME=mini RESOURCE_TYPE=hr RESOURCE_NAME=tuppr

# Compare rendered output against main (needs a local `main`; no worktree)
task flux:diff CLUSTER_NAME=mini

# Test Talos configuration
task talos:generate-clusterconfig CLUSTER_NAME=mini
```

### Recommended Workflow After Making Changes

1. **Make changes** to Flux resources
2. **Quick validate**: `task flux:test-quick CLUSTER_NAME=mini`
3. **Review diff**: `task flux:diff CLUSTER_NAME=mini` (if comparing to main)
4. **Commit** if validation passes
5. **CI will run** full validation with authenticated GHCR access


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

### Adding a New Application (Mini Pattern)

#### First: Determine the Namespace

Before adding an application, decide which Kubernetes namespace it belongs in:

- **Use existing namespace** if the app fits the category (e.g., `observability`, `network`, `database`)
- **Create new namespace** only if:
  - The app represents a new functional category
  - The app requires different security/privilege levels
  - The app is logically isolated from existing namespaces

#### To add an app to an EXISTING namespace

1. Navigate to: `cluster-apps/mini/[namespace]/`
2. Create app directory: `cluster-apps/mini/[namespace]/[app-name]/`
3. Create `app/` subdirectory
4. Add `helmrelease.yaml` with chartRef to OCIRepository
5. Add `ocirepository.yaml` for chart source
6. Add `externalsecret.yaml` if secrets needed
7. Add `app/kustomization.yaml` listing resources
8. Add `ks.yaml` Flux Kustomization with dependencies
9. Add `./[app-name]/ks.yaml` to namespace `kustomization.yaml` resources list
10. Commit and push - Flux will reconcile

#### To create a NEW namespace directory

1. Create directory: `cluster-apps/mini/[namespace-name]/`
2. Create `kustomization.yaml` with:
   - `namespace: [namespace-name]`
   - `components:` - Use `../../components/namespace` (standard) or `../../components/privileged-namespace` (if elevated permissions needed)
   - `resources: []` - Will list app ks.yaml files
3. Follow steps above to add first app
4. Commit and push - Flux will auto-discover the new namespace

### Porting Archived Bitty Config to Mini

Bitty was decommissioned, so there's no live cluster to migrate from. To reuse something from `.archive/bitty/cluster-apps/`, which is on the old pattern:

1. Review the archived app configuration
2. Convert Ingress to HTTPRoute
3. Convert HelmRepository ref to OCIRepository
4. Move SOPS secrets to Doppler + ExternalSecret
5. Remove postBuild substitution from SOPS
6. Add components for namespace/volsync if needed
7. Update versions, since Renovate doesn't track `.archive/`
8. Deploy to Mini
9. Test thoroughly

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
