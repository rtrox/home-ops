# Bitty (archived)

Config for the previous Bitty cluster, 3x Intel NUC nodes with QuickSync. The cluster was decommissioned and this config was archived on 2026-11-04. It's kept for reference for a future rebuild.

## Where the useful facts live

- [`clusters/talos/talconfig.yaml`](clusters/talos/talconfig.yaml): install-disk selectors (`type: nvme`), node IPs, Talos system extensions (i915, intel-ucode, gasket-driver) and machine patches
- [`docs/HARDWARE.md`](../../docs/HARDWARE.md): hardware specs and network ranges for the previous Bitty

## Before reusing anything here

- **Nothing here is deployed.** Flux doesn't read this directory and CI doesn't test it.
- **Versions are stale.** Renovate ignores `.archive/`, so image tags, chart versions and Talos/Kubernetes versions stay as they were on the archive date.
- **URLs and paths reflect the state at archive time.** That includes the mirror-chart URLs in `clusters/bootstrap/helmfile.d/`, which may no longer resolve. Paths such as `./clusters/bitty/...`, `./cluster-apps/bitty/...` and `cluster-apps/base/...` assume the original locations, so copy files back to `clusters/bitty/` and `cluster-apps/bitty/` rather than using them in place.
- **`clusters/talos/*.sops.yaml` stay encrypted.** They're covered by the `*.sops.yaml` rule in the repo's `.sops.yaml`.
