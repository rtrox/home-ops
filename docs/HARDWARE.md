# Hardware Specifications

> Detailed hardware specifications for Chongus and Bitty clusters

## Chongus Cluster

### Dell R730 Nodes (3x)

**Node Configuration:**
- **CPU**: 2x Intel Xeon processors
- **RAM**: High-capacity ECC memory
- **Storage**:
  - 2x Samsung 870 EVO 2TB SSDs per node (6 total for Ceph)
  - Additional system drives
- **GPU**: NVIDIA discrete GPUs with production drivers
- **Network**: Dual 10GbE NICs
- **IPMI**: iDRAC for remote management

**IP Assignments:**
- Node 1: 172.30.11.1
- Node 2: 172.30.11.2
- Node 3: 172.30.11.3

### Storage Configuration

**Rook-Ceph:**
- 6x Samsung 870 EVO 2TB SSDs (2 per node)
- Total raw capacity: 12TB
- Usable capacity: ~4TB (3x replication)

**OpenEBS LocalPV:**
- Path: `/var/mnt/local-hostpath`
- Used for: Cache and temporary storage (Volsync operations)

**NFS:**
- Server: nas.rtrox.io
- Mount paths: `/mnt/rusty/media/*`

## Bitty Cluster

### Intel NUC Nodes (3x)

**Node Configuration:**
- **CPU**: Intel Core processors (newer generation, fewer cores than Chongus)
- **RAM**: DDR4 SO-DIMM
- **Storage**: NVMe SSDs (faster than Chongus SATA SSDs)
- **GPU**: Intel iGPU with QuickSync support
- **Network**: Gigabit Ethernet

**IP Assignments:**
- Node 1: 172.30.21.1
- Node 2: 172.30.21.2
- Node 3: 172.30.21.3

## Mini Cluster

### Minisforum MS-A2 Nodes (3x)

**Node Configuration:**
- **CPU**: AMD Ryzen
- **GPU**: AMD iGPU (amdgpu extension enabled)
- **Storage**: Dual NVMe per node - 2TB boot disk, 4TB storage disk (reserved for future Rook-Ceph use)
- **Network**: Gigabit Ethernet

**IP Assignments:**
- Node 1: 172.21.31.1
- Node 2: 172.21.31.2
- Node 3: 172.21.31.3

## Network Infrastructure

**Load Balancer IP Pools (Cilium LBIPAM, one distinct pool per cluster since these networks are routable to each other):**
- Chongus: 172.22.12.0/24
  - 172.22.12.1: envoy-internal gateway
  - 172.22.12.2: envoy-external gateway
- Bitty: 172.19.12.0/24
- Mini: 172.19.32.0/24

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
