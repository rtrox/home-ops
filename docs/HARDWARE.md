# Hardware Specifications

> Detailed hardware specifications for Mini and Bitty clusters

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

## Bitty Cluster

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
- Bitty: 172.19.12.0/24

**Pod Network:**
- CIDR: 10.244.0.0/16
- Managed by: Cilium CNI

**Service Network:**
- CIDR: 10.96.0.0/12
- DNS: CoreDNS

## Supporting Infrastructure

**NAS (nas.rtrox.io):**
- Storage backend for shared media
- NFS exports for cluster mounts

**Network:**
- Internal LAN with VLAN segmentation
- Internet egress via Cloudflare Tunnel
- Tailscale for remote access
