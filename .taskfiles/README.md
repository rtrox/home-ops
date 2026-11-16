# Taskfile Reference

This document describes the available [Task](https://taskfile.dev/) commands for managing the home-ops infrastructure.

## Prerequisites

All tasks require tools managed via [mise](https://mise.jdx.dev/):

```bash
mise install
```

## Global Variables

Most tasks require `CLUSTER_NAME` to be set:

```bash
# Set for individual commands
task flux:test CLUSTER_NAME=mini

# Or export for the session
export CLUSTER_NAME=mini
```

---

## Flux Tasks

Tasks for validating and inspecting Flux resources.

### `flux:test`

Validate all Flux resources with flux-local.

```bash
task flux:test CLUSTER_NAME=mini
```

### `flux:build`

Build Flux resources (Kustomizations or HelmReleases).

```bash
# Build all Kustomizations
task flux:build CLUSTER_NAME=mini

# Build HelmReleases
task flux:build CLUSTER_NAME=mini RESOURCE_TYPE=hr

# Build a specific resource
task flux:build CLUSTER_NAME=mini RESOURCE_NAME=qbittorrent
```

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TYPE` | `ks` | Resource type: `ks` (Kustomization) or `hr` (HelmRelease) |
| `RESOURCE_NAME` | (all) | Specific resource name to build |

### `flux:list`

List Flux resources.

```bash
task flux:list CLUSTER_NAME=mini
task flux:list CLUSTER_NAME=mini RESOURCE_TYPE=hr
```

### `flux:diff`

Compare Flux resources against a base branch.

```bash
# Diff against main
task flux:diff CLUSTER_NAME=mini

# Diff HelmReleases against a different branch
task flux:diff CLUSTER_NAME=mini RESOURCE_TYPE=hr BASE_BRANCH=develop
```

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TYPE` | `hr` | Resource type: `ks` or `hr` |
| `BASE_BRANCH` | `main` | Branch to compare against |

### `flux:diff-all`

Compare both Kustomizations and HelmReleases against main.

```bash
task flux:diff-all CLUSTER_NAME=mini
```

---

## Talos Tasks

Tasks for managing Talos Linux nodes.

### `talos:generate-clusterconfig`

Render Talos machine configurations and the `talosconfig` using [topf](https://github.com/postfinance/topf). Output goes to `clusterconfig/` (gitignored).

```bash
task talos:generate-clusterconfig CLUSTER_NAME=mini
```

**Inputs** (all in `clusters/<cluster>/talos/`):
- `topf.yaml` - Cluster and node definitions (Talos/Kubernetes versions, schematics, secureboot)
- `secrets.sops.yaml` - Encrypted cluster secrets (topf decrypts it with SOPS)
- `schematic*.yaml` - Image Factory schematics (per node via `schematicId: "@file"`)
- `all/`, `control-plane/`, `worker/`, `node/<host>/` - Strategic-merge patches, applied in that order (`.yaml.tpl` files are Go templates)

### `talos:validate-clusterconfig`

Render every node config and run `talosctl validate --mode metal` on each. Run this before applying, and in particular after any Talos version bump: Talos 1.14 rejects configs that set the same thing in both a legacy v1alpha1 field and its new document.

```bash
task talos:validate-clusterconfig CLUSTER_NAME=mini
```

### `talos:apply-clusterconfig`

Apply machine configurations to all nodes in a cluster.

```bash
# Normal apply
task talos:apply-clusterconfig CLUSTER_NAME=mini

# Dry run (exits 2 if any node would change)
task talos:apply-clusterconfig CLUSTER_NAME=mini DRY_RUN=true
```

topf applies configs itself and detects nodes in maintenance mode, so no insecure flag is needed for a first bootstrap.

| Variable | Default | Description |
|----------|---------|-------------|
| `DRY_RUN` | `false` | Preview changes without applying |

### `talos:apply-node`

Apply configuration to a single node (supports `DRY_RUN=true`).

```bash
task talos:apply-node CLUSTER_NAME=mini NODE=node01
```

### `talos:upgrade-node`

Break-glass Talos upgrade of one node. Normal upgrades are done by tuppr (`system-upgrade/tuppr`), not this task.

```bash
task talos:upgrade-node CLUSTER_NAME=mini NODE=node01
```

---

## Bootstrap Tasks

Tasks for bootstrapping a new Kubernetes cluster.

### `k8s-bootstrap:talos-cluster`

Bootstrap the Talos cluster and generate kubeconfig.

```bash
task k8s-bootstrap:talos-cluster CLUSTER_NAME=mini
```

This will:
1. Select a random controller node
2. Bootstrap the Talos cluster
3. Generate kubeconfig with the cluster context

### `k8s-bootstrap:apps`

Bootstrap core applications and CRDs.

```bash
task k8s-bootstrap:apps CLUSTER_NAME=mini
```

This will:
1. Create namespaces
2. Inject Doppler token for external-secrets
3. Apply CRDs via helmfile
4. Sync core apps via helmfile

**Note:** This task prompts for confirmation before proceeding.

---

## Volsync Tasks

Tasks for interacting with Volsync backups using restic.

### `volsync:restic-env`

Print restic environment variables for use with `eval`.

```bash
# MinIO backend (default)
eval $(task volsync:restic-env APP=qbittorrent NAMESPACE=downloads)

# B2 backend
eval $(task volsync:restic-env APP=qbittorrent NAMESPACE=downloads BACKEND=b2)

# Then use restic directly
restic snapshots
restic ls latest
```

| Variable | Default | Description |
|----------|---------|-------------|
| `APP` | (required) | Application name |
| `NAMESPACE` | (required) | Kubernetes namespace |
| `BACKEND` | `minio` | Backup backend: `minio` or `b2` |

### `volsync:snapshots`

List restic snapshots for an application.

```bash
task volsync:snapshots APP=qbittorrent NAMESPACE=downloads
task volsync:snapshots APP=qbittorrent NAMESPACE=downloads BACKEND=b2
```

### `volsync:ls`

List files in a snapshot.

```bash
# List files in latest snapshot
task volsync:ls APP=qbittorrent NAMESPACE=downloads

# List files in a specific snapshot
task volsync:ls APP=qbittorrent NAMESPACE=downloads SNAPSHOT=abc123
```

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAPSHOT` | `latest` | Snapshot ID to list |

### `volsync:stats`

Show repository statistics.

```bash
task volsync:stats APP=qbittorrent NAMESPACE=downloads
```

### `volsync:unlock`

Remove stale locks from the repository.

```bash
task volsync:unlock APP=qbittorrent NAMESPACE=downloads
```

Use this when a backup was interrupted and left a lock behind.

---

## Examples

### Full Cluster Bootstrap

```bash
# 1. Generate Talos configs
task talos:generate-clusterconfig CLUSTER_NAME=mini

# 2. Apply to nodes (topf handles maintenance mode itself)
task talos:apply-clusterconfig CLUSTER_NAME=mini

# 3. Bootstrap Talos
task k8s-bootstrap:talos-cluster CLUSTER_NAME=mini

# 4. Deploy apps
task k8s-bootstrap:apps CLUSTER_NAME=mini
```

### Validate Changes Before PR

```bash
# Test all Flux resources
task flux:test CLUSTER_NAME=mini

# See what will change
task flux:diff-all CLUSTER_NAME=mini
```

### Restore a Backup

```bash
# Check available snapshots
task volsync:snapshots APP=paperless-ngx NAMESPACE=default

# List files in a snapshot
task volsync:ls APP=paperless-ngx NAMESPACE=default SNAPSHOT=latest

# For actual restore, use restic directly
eval $(task volsync:restic-env APP=paperless-ngx NAMESPACE=default)
restic restore latest --target /tmp/restore
```

### Debug a Locked Repository

```bash
# Check if locked
task volsync:snapshots APP=myapp NAMESPACE=default
# If you see "repository is already locked", run:
task volsync:unlock APP=myapp NAMESPACE=default
```
