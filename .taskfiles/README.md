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

Validate all Flux resources with [flate](https://github.com/home-operations/flate), rendering every HelmRelease.

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

Compare the rendered Flux resources against a Git revision (no temporary worktree needed).

```bash
# Diff against main
task flux:diff CLUSTER_NAME=mini

# Diff HelmReleases against a different branch
task flux:diff CLUSTER_NAME=mini RESOURCE_TYPE=hr BASE_BRANCH=develop
```

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_TYPE` | `all` | Resource type: `all`, `ks`, `hr` or `images` |
| `BASE_BRANCH` | `main` | Revision to compare against |

### `flux:diff-all`

Compare everything against main (alias for `flux:diff` with `RESOURCE_TYPE=all`).

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
| `CONFIRM` | (prompt) | Set `false` to skip topf's confirmation prompt. Required without a terminal: topf auto-declines and skips the apply, and the task still exits 0 |

### `talos:apply-node`

Apply configuration to a single node (supports `DRY_RUN=true`).

```bash
task talos:apply-node CLUSTER_NAME=mini NODE=node01
task talos:apply-node CLUSTER_NAME=mini NODE=node01 CONFIRM=false  # non-interactive
```

Applying restarts that node's kube-apiserver static pod, and topf's dry-run reports the node as not ready until it is back. Do one node at a time and re-run the dry-run afterwards: every node must say "no changes to apply".

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

## Ansible Tasks

Tasks for the Ansible-managed single-board computers (see [ansible/README.md](../ansible/README.md)). They run under `doppler run -p hosts-at-home -c prd --` (so roles can read secrets from the environment), and always run with `--forks 1` so group targets are applied one host at a time.

### `ansible:syntax`

Syntax-check the playbook.

```bash
task ansible:syntax
```

### `ansible:check`

Dry-run against a host or group, showing file diffs.

```bash
task ansible:check HOST=ns2.rtrox.io
```

### `ansible:apply`

Apply to a host or group. Extra `ansible-playbook` flags go after `--`.

```bash
task ansible:apply HOST=ns2.rtrox.io
task ansible:apply HOST=dns -- -v
```

### `ansible:upgrade`

Upgrade OS packages and reboot, one host at a time (`ansible/upgrade.yaml`). On DNS hosts it checks that the other name server is answering before starting, and waits for DNS to come back afterwards. Add `-- --check` for a dry run.

```bash
task ansible:upgrade HOST=ns2.rtrox.io -- --check
task ansible:upgrade HOST=dns
```

---

## Volsync Tasks

Tasks for interacting with Volsync backups using restic.

### `volsync:restic-shell`

Open a shell with the restic credentials in its environment (nothing is printed).

```bash
# MinIO backend (default)
task volsync:restic-shell APP=qbittorrent NAMESPACE=downloads

# B2 backend
task volsync:restic-shell APP=qbittorrent NAMESPACE=downloads BACKEND=b2

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
task volsync:restic-shell APP=paperless-ngx NAMESPACE=default
restic restore latest --target /tmp/restore
```

### Debug a Locked Repository

```bash
# Check if locked
task volsync:snapshots APP=myapp NAMESPACE=default
# If you see "repository is already locked", run:
task volsync:unlock APP=myapp NAMESPACE=default
```
