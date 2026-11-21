# Proxmox host (`pve.rtrox.io`)

Single Proxmox VE node at `172.21.1.21`. Managed with Ansible (`ansible/proxmox.yaml`, role
`proxmox`); VMs will be defined in Terraform (`terraform-record/proxmox`, not yet created).

## Hardware

Intel NUC10i5FNK (i5-10210U, 4C/8T, VT-x), 64 GB RAM, one 512 GB Samsung NVMe, one gigabit NIC.
No second drive: the slim chassis has no 2.5" bay, so assume no extra storage. A 2242 SATA M.2 may
fit a second slot; unverified.

## Layout and decisions

| Item | Choice |
| --- | --- |
| Install | Proxmox VE 9.x on Debian 13, `no-subscription` repo, standalone node |
| Disk | LVM-thin on the NVMe: `root` 96 GB, `data` thin pool (VM disks), swap 8 GB |
| VM disks | `local-lvm` (local NVMe, independent of the NAS) |
| Backups | vzdump to NFS (`truenas-nfs` = `nas.rtrox.io:/mnt/rusty/proxmox-nfs`) |
| NFS export | allowed host `172.21.1.21`, mapall to a dedicated `proxmox` user |
| Removed | TrueNAS iSCSI plugin and apt repo, enterprise repos, the old `restreamer` VM |
| DNS on the host | `1.1.1.1` (does not depend on the other site's resolvers) |
| Subscription popup | Hidden by a patch that an apt hook reapplies after upgrades |

## Access

- Named admin user with sudo and the GitHub keys; SSH is key-only, root by key only.
- Web UI login uses the admin user (realm *Linux PAM*), Administrator role, with TOTP.
- The admin username is deliberately not written in this repo; see `ansible/CLAUDE.md`.

## Still to do

Trusted certificate (ACME, Cloudflare DNS-01) then WebAuthn; firewall; remote access; monitoring
and alerts; vzdump jobs and a restore test; drop root key login; Terraform stack for VMs.
