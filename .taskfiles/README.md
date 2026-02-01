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
task flux:test CLUSTER_NAME=chongus

# Or export for the session
export CLUSTER_NAME=chongus
```

---

## Flux Tasks

Tasks for validating and inspecting Flux resources.

### `flux:test`

Validate all Flux resources with flux-local.

```bash
task flux:test CLUSTER_NAME=chongus
```

### `flux:build`

Build Flux resources (Kustomizations or HelmReleases).

```bash
# Build all Kustomizations
task flux:build CLUSTER_NAME=chongus

# Build HelmReleases
task flux:build CLUSTER_NAME=chongus RESOURCE_TYPE=hr

# Build a specific resource
task flux:build CLUSTER_NAME=chongus RESOURCE_NAME=qbittorrent
```

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TYPE` | `ks` | Resource type: `ks` (Kustomization) or `hr` (HelmRelease) |
| `RESOURCE_NAME` | (all) | Specific resource name to build |

### `flux:list`

List Flux resources.

```bash
task flux:list CLUSTER_NAME=chongus
task flux:list CLUSTER_NAME=chongus RESOURCE_TYPE=hr
```

### `flux:diff`

Compare Flux resources against a base branch.

```bash
# Diff against main
task flux:diff CLUSTER_NAME=chongus

# Diff HelmReleases against a different branch
task flux:diff CLUSTER_NAME=chongus RESOURCE_TYPE=hr BASE_BRANCH=develop
```

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TYPE` | `hr` | Resource type: `ks` or `hr` |
| `BASE_BRANCH` | `main` | Branch to compare against |

### `flux:diff-all`

Compare both Kustomizations and HelmReleases against main.

```bash
task flux:diff-all CLUSTER_NAME=chongus
```

---

## Talos Tasks

Tasks for managing Talos Linux nodes.

### `talos:generate-clusterconfig`

Generate Talos machine configurations using talhelper.

```bash
task talos:generate-clusterconfig CLUSTER_NAME=chongus
```

**Prerequisites:**
- `talsecret.sops.yaml` - Encrypted cluster secrets
- `talconfig.yaml` - Cluster configuration
- `talenv.sops.yaml` - Environment variables

### `talos:apply-clusterconfig`

Apply machine configurations to all nodes in a cluster.

```bash
# Normal apply
task talos:apply-clusterconfig CLUSTER_NAME=chongus

# Dry run
task talos:apply-clusterconfig CLUSTER_NAME=chongus DRY_RUN=true

# Insecure mode (for initial bootstrap)
task talos:apply-clusterconfig CLUSTER_NAME=chongus INSECURE=true
```

| Variable | Default | Description |
|----------|---------|-------------|
| `DRY_RUN` | `false` | Preview changes without applying |
| `INSECURE` | `false` | Skip TLS verification (for new nodes) |

### `talos:apply-node`

Apply configuration to a single node.

```bash
task talos:apply-node CLUSTER_NAME=chongus NODE=chongus-01
```

### `talos:upgrade-node`

Upgrade Talos on a single node.

```bash
task talos:upgrade-node CLUSTER_NAME=chongus NODE=chongus-01
```

---

## Bootstrap Tasks

Tasks for bootstrapping a new Kubernetes cluster.

### `k8s-bootstrap:talos-cluster`

Bootstrap the Talos cluster and generate kubeconfig.

```bash
task k8s-bootstrap:talos-cluster CLUSTER_NAME=chongus
```

This will:
1. Select a random controller node
2. Bootstrap the Talos cluster
3. Generate kubeconfig with the cluster context

### `k8s-bootstrap:apps`

Bootstrap core applications and CRDs.

```bash
task k8s-bootstrap:apps CLUSTER_NAME=chongus
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
task talos:generate-clusterconfig CLUSTER_NAME=chongus

# 2. Apply to nodes (insecure for first time)
task talos:apply-clusterconfig CLUSTER_NAME=chongus INSECURE=true

# 3. Bootstrap Talos
task k8s-bootstrap:talos-cluster CLUSTER_NAME=chongus

# 4. Deploy apps
task k8s-bootstrap:apps CLUSTER_NAME=chongus
```

### Validate Changes Before PR

```bash
# Test all Flux resources
task flux:test CLUSTER_NAME=chongus

# See what will change
task flux:diff-all CLUSTER_NAME=chongus
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
