# Hardware Specifications

> Detailed hardware specifications for the Mini cluster, the previous Bitty cluster, and the Ansible-managed single-board computers

## Mini Cluster

### Minisforum MS-A2 Nodes (3x)

**Node Configuration:**
- **CPU**: AMD Ryzen
- **GPU**: AMD iGPU on every node (amdgpu extension); node03 additionally has an NVIDIA RTX 3050
- **Storage**: Dual NVMe per node - 2TB boot disk, 4TB storage disk (Rook-Ceph)
- **Network**: Gigabit Ethernet

**IP Assignments:**
- Node 1: 172.21.31.1
- Node 2: 172.21.31.2
- Node 3: 172.21.31.3

### Storage Configuration

**Rook-Ceph:**
- 3x 4TB NVMe (1 per node)
- Storage Class: `ceph-block` (default)
- Replication: 3 replicas

## Previous Bitty Cluster (Decommissioned)

> These facts describe the previous Bitty, kept as reference for a planned rebuild. Its config is archived at `.archive/bitty/`, and its install-disk selectors, Talos extensions and machine patches are in `.archive/bitty/clusters/talos/talconfig.yaml`.

### Intel NUC Nodes (3x)

**Node Configuration:**
- **CPU**: Intel Core processors
- **RAM**: DDR4 SO-DIMM
- **Storage**: NVMe SSDs
- **GPU**: Intel iGPU with QuickSync support
- **Network**: Gigabit Ethernet

**IP Assignments:**
- Node 1: 172.30.21.1
- Node 2: 172.30.21.2
- Node 3: 172.30.21.3

## Network Infrastructure

**Load Balancer IP Pools (Cilium LBIPAM, one distinct pool per cluster since these networks are routable to each other):**
- Mini: 172.19.32.0/24
  - 172.19.32.1: envoy-internal gateway
  - 172.19.32.2: envoy-external gateway
- Previous Bitty (decommissioned): 172.19.12.0/24

**Pod Network:**
- CIDR: 10.244.0.0/16
- Managed by: Cilium CNI

**Service Network:**
- CIDR: 10.96.0.0/12
- DNS: CoreDNS

## Supporting Infrastructure

### Single-Board Computers (Ansible-managed)

Not part of any Kubernetes cluster. Configured by the playbook in [`ansible/`](../ansible/README.md), and every service on them runs as a Docker container under systemd.

| Host             | Address     | Board                   | OS                          | RAM  | Storage                 | Role                                           |
| ---------------- | ----------- | ----------------------- | --------------------------- | ---- | ----------------------- | ---------------------------------------------- |
| `ns1.rtrox.io`   | 172.30.99.1 | Raspberry Pi 5 Model B  | Debian 12 (bookworm), arm64 | 4GB  | 64GB SD card (boot + root) | DNS (Blocky), keepalived `MASTER`, Tailscale   |
| `ns2.rtrox.io`   | 172.30.99.2 | Orange Pi 5 Pro         | Armbian (bookworm), arm64   | 8GB  | 500GB NVMe root (WD `WDS500G2B0C`), 32GB SD card for `/boot` | DNS (Blocky), keepalived `BACKUP`, Tailscale |
| `avahi.rtrox.io` | 172.30.99.3 | Raspberry Pi (model not recorded) | -                 | -    | -                       | Avahi mDNS reflector across VLANs 200 and 300  |

- ns1 and ns2 share a keepalived virtual IP for DNS, so either one can be down for maintenance as long as the other is healthy.
- Every board runs `raspi-monitor`, which drives an I2C OLED status display. The role handles both Raspberry Pi and Orange Pi I2C setup.

**NAS (nas.rtrox.io):**
- Storage backend for shared media
- NFS exports for cluster mounts

**Network:**
- Internal LAN with VLAN segmentation
- Internet egress via Cloudflare Tunnel
- Tailscale for remote access
