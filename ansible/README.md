# Ansible

Configuration for the non-Kubernetes machines: the Raspberry Pi / Orange Pi boxes that run DNS (`ns1`, `ns2`) and the mDNS reflector (`avahi`). Everything here runs as Docker containers managed by systemd units, so each role mostly templates a `.service` file and enables it.

## Hosts

| Host             | Address     | Group   | Notes                                        |
| ---------------- | ----------- | ------- | -------------------------------------------- |
| `ns1.rtrox.io`   | 172.30.99.1 | `dns`   | Blocky + keepalived `MASTER`, Tailscale      |
| `ns2.rtrox.io`   | 172.30.99.2 | `dns`   | Blocky + keepalived `BACKUP`, Tailscale      |
| `avahi.rtrox.io` | 172.30.99.3 | `avahi` | VLAN interfaces (200, 300) + Avahi reflector |
| `pve.rtrox.io`   | 172.21.1.21 | `proxmox` | Proxmox VE host, run with `proxmox.yaml` (see [docs/proxmox](../docs/proxmox/README.md)) |

## Setup

The hosts live in the committed [`inventory/hosts.yaml`](../inventory/hosts.yaml) (see [inventory/README.md](../inventory/README.md)); `ansible.cfg` points at it. Hosts in its `unmanaged` group need DNS but run no plays, and the plays exclude them. Before running anything you need:

- **Two Doppler secrets** in `hosts-at-home/prd`: `ANSIBLE_SSH_USER` (the SSH user on the Pis) and `PROXMOX_ADMIN_USER` (the Proxmox admin account, also its SSH user). The committed `inventory/group_vars/` files read them with `lookup('env', ...)`, and the `task ansible:*` tasks run under `doppler run -p hosts-at-home -c prd --`, so a fresh clone needs only a Doppler login. Running `ansible-playbook` directly, outside `task`, fails with a hint before connecting. Set them once:

  ```sh
  read 'U?SSH user: '; print -rn -- "$U" | doppler secrets set ANSIBLE_SSH_USER -p hosts-at-home -c prd --silent
  read 'U?Proxmox admin user: '; print -rn -- "$U" | doppler secrets set PROXMOX_ADMIN_USER -p hosts-at-home -c prd --silent; unset U
  ```

- **`.ansible-vault-pass`**: the Ansible Vault password, mode `600`.

The `geerlingguy.docker` role is installed from Galaxy, not vendored:

```sh
ansible-galaxy role install geerlingguy.docker
ansible-galaxy collection install community.general
```

SSH access is by key only (`secure-ssh` disables password auth), and the `ansible_user` needs passwordless sudo, since every play runs with `become: true`.

## Proxmox

`pve.rtrox.io` has its own playbook, `proxmox.yaml`, with the `proxmox` role. It is kept out of
`site.yaml` so it never needs the vault password. The group vars set its SSH user and the
admin account name, both from Doppler `PROXMOX_ADMIN_USER` (see Setup).

```sh
task ansible:proxmox-check -- -e proxmox_ssh_harden=true   # dry run
task ansible:proxmox-apply
```

On a fresh host, connect as root once with `-e proxmox_ssh_harden=false`, confirm the admin user
can log in by key, then run again with hardening on.

## Running

From the repo root, via [Task](../.taskfiles/README.md#ansible-tasks):

```sh
task ansible:syntax                     # syntax-check the playbook
task ansible:check HOST=ns2.rtrox.io    # dry run, showing file diffs
task ansible:apply HOST=ns2.rtrox.io    # apply
task ansible:upgrade HOST=ns2.rtrox.io  # OS upgrade + reboot (add -- --check for a dry run)
```

`HOST` can be a single host or a group (`dns`). Tasks always run with `--forks 1`, so a group is applied one host at a time. Extra flags go after `--`, e.g. `task ansible:check HOST=dns -- -v`.

`ansible:upgrade` runs `upgrade.yaml`: one host at a time, and on DNS hosts it first checks that the other name server is answering, then `apt dist-upgrade`, reboots if packages changed or a reboot is pending (`/var/run/reboot-required`), and waits until the host answers DNS again. It stops at the first host that fails, so a bad upgrade on one name server never reaches the other.

Apply one DNS server at a time. Restarting Docker (any `daemon.json` change does it) briefly takes DNS down on that host, and keepalived only covers for it if the other one is healthy.

## Playbook layout (`site.yaml`)

1. **All hosts**: `journald`, `armbian`, `raspberry-pi`, `auto-upgrade`, `secure-ssh`, `geerlingguy.docker`, `raspi-monitor`, `node-exporter`, then hostname, UTC timezone and common packages.
2. **`dns`**: `valkey`, `blocky`, `alloy`, `keepalived`, `tailscaled`. Loads `blocky_secrets.yaml`, `keepalived_secrets.yaml` and `valkey_secrets.yaml`.
3. **`avahi`**: `vlans`, `avahi`.

## Roles

| Role             | In `site.yaml` | What it does                                                                                       |
| ---------------- | -------------- | -------------------------------------------------------------------------------------------------- |
| `journald`       | yes            | Keeps the systemd journal in RAM (`Storage=volatile`, capped at 128M) to spare SD cards. Docker logs to journald (`site.yaml`), so container output stays in RAM too; read it with `docker logs` or `journalctl CONTAINER_NAME=<name>`. Logs don't survive a reboot |
| `armbian`        | yes            | On Armbian hosts, keeps apt on the stable repo (`apt.armbian.com`) instead of the nightly `beta.armbian.com` |
| `raspberry-pi`   | yes            | On Raspberry Pis, appends `cgroup_enable=memory cgroup_memory=1` to `/boot/firmware/cmdline.txt` (the Pi 5 firmware itself adds `cgroup_disable=memory`, so Docker memory limits weren't enforced). Keeps the original as `cmdline.txt.bak` and marks a reboot as pending; `task ansible:upgrade` then reboots safely |
| `auto-upgrade`   | yes            | Daily `unattended-upgrades` from Debian (main, security, updates) and Docker on every host, plus the Raspberry Pi repo on Pis and the Armbian repo on Armbian hosts (detected per host), rebooting right after an upgrade that requires it. On `dns` hosts, the run is skipped unless every other DNS server answers (`/usr/local/sbin/dns-peer-check`, an `ExecCondition`; skips are logged in `journalctl -u apt-daily-upgrade`). Each host gets its own 30-minute slot starting 09:00 UTC (by position in the sorted inventory: avahi 09:00, ns1 09:30, ns2 10:00), so name servers never upgrade or reboot together. Override with `auto_upgrade_slot` / `auto_upgrade_base_time` |
| `secure-ssh`     | yes            | Syncs `authorized_keys` from `github.com/<user>.keys` and/or `ssh_public_keys`, then disables password auth (refuses to if no keys ended up in the file) |
| `raspi-monitor`  | yes (opt-in)   | Enables I2C (Raspberry Pi or Orange Pi) and runs the OLED status display container. Off unless `raspi_monitor_enabled: true` is set for the host; when off, it stops and disables any existing unit |
| `node-exporter`  | yes            | Prometheus node-exporter container                                                                 |
| `valkey`         | yes (`dns`)    | Valkey container used as Blocky's shared cache. Runs on both DNS hosts; Blocky on both connects through the keepalived VIP, so whichever host holds the VIP serves the cache for both. No persistence, password required |
| `blocky`         | yes            | Blocky DNS container, frees port 53 from systemd-resolved, pins `/etc/resolv.conf`. Syncs its cache and blocking state with the other DNS host through Valkey (optional: DNS keeps working without it) |
| `alloy`          | yes (`dns`)    | Grafana Alloy container that ships the host's in-RAM journal to Loki on Mini (`loki-lan`, 172.19.32.200), including Blocky's per-query JSON lines as `stream="dns-query"`. Writes nothing to disk: positions on a tmpfs, unsent logs in memory only. In Grafana: `{host="ns1"}` for host logs, `{stream="dns-query"} \| json` for queries |
| `keepalived`     | yes            | VRRP virtual IP shared between ns1/ns2 (v4 and v6, kept in sync). A host gives up the VIP when its local DNS server stops accepting connections on port 53 (`chk_dns`, ~6s to detect), so the peer takes over; tested at ~5s of VIP downtime when Blocky stops on the holder |
| `tailscaled`     | yes            | Tailscale daemon container (pinned by digest; Renovate updates it)                                 |
| `vlans`          | yes            | 802.1q VLAN interfaces via NetworkManager                                                          |
| `avahi`          | yes            | Avahi mDNS reflector container (masks the host's own avahi-daemon)                                 |

Role variables and their defaults live in each role's `defaults/main.yaml`.

## Secrets

All secrets files are Ansible Vault-encrypted, named `<thing>_secrets.yaml`:

| File                      | Used by                              |
| ------------------------- | ------------------------------------ |
| `blocky_secrets.yaml`     | `blocky` (upstream, Postgres address) |
| `valkey_secrets.yaml`     | `valkey`, `blocky` (Valkey password)  |
| `keepalived_secrets.yaml` | `keepalived` (VIP, auth password)    |

```sh
ansible-vault edit --vault-password-file .ansible-vault-pass blocky_secrets.yaml
```

Never commit a decrypted secrets file. The `ansible-vault-encrypted` pre-commit hook (also run in CI) rejects any `*_secrets.yaml` without the `$ANSIBLE_VAULT;` header.

## Linting

`ansible/` is covered by the repo's yamllint config (`.github/lint/.yamllint.yaml`), except the vault-encrypted `*_secrets.yaml` files. It runs in pre-commit and CI.
