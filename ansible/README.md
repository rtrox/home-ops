# Ansible

Configuration for the non-Kubernetes machines: the Raspberry Pi / Orange Pi boxes that run DNS (`ns1`, `ns2`) and the mDNS reflector (`avahi`). Everything here runs as Docker containers managed by systemd units, so each role mostly templates a `.service` file and enables it.

## Hosts

| Host             | Address     | Group   | Notes                                        |
| ---------------- | ----------- | ------- | -------------------------------------------- |
| `ns1.rtrox.io`   | 172.30.99.1 | `dns`   | Blocky + keepalived `MASTER`, Tailscale      |
| `ns2.rtrox.io`   | 172.30.99.2 | `dns`   | Blocky + keepalived `BACKUP`, Tailscale      |
| `avahi.rtrox.io` | 172.30.99.3 | `avahi` | VLAN interfaces (200, 300) + Avahi reflector |
| `dns-a1.rtrox.io` | 172.21.99.1 | `dns_apartment` (in `vms`) | Apartment resolver (Proxmox VM): Blocky + Valkey, no keepalived |
| `pve.rtrox.io`   | 172.21.1.21 | `proxmox` | Proxmox VE host, run with `proxmox.yaml` (see [docs/proxmox](../docs/proxmox/README.md)) |

## Setup

The hosts live in the committed [`inventory/hosts.yaml`](../inventory/hosts.yaml) (see [inventory/README.md](../inventory/README.md)); `ansible.cfg` points at it. Hosts in its `unmanaged` group need DNS but run no plays, and the plays exclude them. Before running anything you need:

- **The SSH user** is `rtrox` everywhere (committed in `inventory/group_vars/all.yaml`). The `admin-user` role creates it with a locked password, passwordless sudo and the GitHub keys. On a brand-new host, bootstrap once as its original user: `task ansible:apply HOST=<host> -- -e ansible_user=<user>`.

- **Doppler**: `doppler login`; the tasks read `ansible/prd` and `hosts-at-home/prd`.

The `geerlingguy.docker` role is installed from Galaxy, not vendored:

```sh
ansible-galaxy role install geerlingguy.docker
ansible-galaxy collection install community.general
```

SSH access is by key only (`secure-ssh` disables password auth), and the `ansible_user` needs passwordless sudo, since every play runs with `become: true`.

## Proxmox

`pve.rtrox.io` has its own playbook, `proxmox.yaml`, with the `proxmox` role. It is kept out of
`site.yaml`. The group vars set its SSH user and the
admin account name, both `rtrox` (see Setup).

```sh
task ansible:proxmox-check -- -e proxmox_ssh_harden=true   # dry run
task ansible:proxmox-apply
```

On a fresh host, connect as root once with `-e proxmox_ssh_harden=false`, confirm the admin user
can log in by key, then run again with hardening on.

## Apartment DNS (`dns-a1`)

`dns-a1` is a Proxmox VM (Debian 13) in the `dns_apartment` group, with its own play in `site.yaml`: `admin-user`, `secure-ssh`, `geerlingguy.docker`, `node-exporter`, `valkey`, `blocky`, plus `qemu-guest-agent`. It skips the Pi-only roles and keepalived. Its per-site settings are in `inventory/group_vars/dns_apartment.yaml` (Valkey on its own address, the apartment router for client-name lookups). `dns-a2` will be Blocky in mini and connect to the Valkey on dns-a1. The house Pis (`dns`) keep their own Valkey behind the keepalived VIP and are untouched by this play.

```sh
task ansible:check HOST=dns-a1.rtrox.io   # dry run first
task ansible:apply HOST=dns-a1.rtrox.io
```

Verify (the API is on port 80):

```sh
dig @172.21.99.1 example.com
dig @172.21.99.1 doubleclick.net                    # a blocked name answers 0.0.0.0
curl http://172.21.99.1/api/blocking/status
curl 'http://172.21.99.1/api/blocking/disable?duration=10m'   # pauses blocking (shared through Valkey)
```

TODO: dns-a1 reuses the house's Valkey password until migration phase 3 gives each site its own.

### One Blocky config

Blocky's upstreams (DoH to Cloudflare and Quad9, with their IPs as bootstrap resolvers), blocklists, allowlists, client groups and caching live once in [`cluster-apps/components/blocky/00-shared.yaml`](../cluster-apps/components/blocky/00-shared.yaml). The `blocky` role copies it to `/etc/blocky/00-shared.yaml` and renders the per-host settings (ports, Valkey address, query log, `clientLookup`, Prometheus) from `roles/blocky/templates/host.yaml.j2` to `/etc/blocky/10-host.yaml`. Blocky runs with `--config /etc/blocky` and merges every YAML file in the folder in alphabetical order (mappings merge, lists are replaced, so keep each key in one file). The same file is rendered into mini's ConfigMap for dns-a2 (`cluster-apps/components/blocky`, a Kustomize component, since Flux only reads files below a Kustomization's path). Editing the shared file means re-applying every resolver (one at a time).

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
2. **`dns`**: `valkey`, `blocky`, `alloy`, `keepalived`, `tailscaled`.
3. **`dns_apartment`** (dns-a1): `admin-user`, `secure-ssh`, `geerlingguy.docker`, `node-exporter`, `valkey`, `blocky`, then `qemu-guest-agent` and a few packages.
4. **`avahi`**: `vlans`, `avahi`.
5. **`runners`** (runner.rtrox.io): `admin-user`, `secure-ssh`, `geerlingguy.docker`, `github-runner`, plus `qemu-guest-agent`. The role needs `GITHUB_RUNNER_APP`, `CI_DOPPLER_TF_READ` and `CI_DOPPLER_HOSTS_READ` from `hosts-at-home/prd` (the `task ansible:*` wrapper provides them).

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
| `valkey`         | yes (`dns`, `dns_apartment`) | Valkey container used as Blocky's shared cache. At the house it runs on both DNS hosts; Blocky on both connects through the keepalived VIP, so whichever host holds the VIP serves the cache for both. No persistence, password required |
| `blocky`         | yes            | Blocky DNS container (config: the shared `cluster-apps/components/blocky/00-shared.yaml` plus a per-host file), frees port 53 from systemd-resolved, pins `/etc/resolv.conf`. Syncs its cache and blocking state with the other DNS host through Valkey (optional: DNS keeps working without it) |
| `alloy`          | yes (`dns`)    | Grafana Alloy container that ships the host's in-RAM journal to Loki on Mini (`loki-lan`, 172.19.32.200), including Blocky's per-query JSON lines as `stream="dns-query"`. Writes nothing to disk: positions on a tmpfs, unsent logs in memory only. In Grafana: `{host="ns1"}` for host logs, `{stream="dns-query"} \| json` for queries |
| `keepalived`     | yes            | VRRP virtual IP shared between ns1/ns2 (v4 and v6, kept in sync). A host gives up the VIP when its local DNS server stops accepting connections on port 53 (`chk_dns`, ~6s to detect), so the peer takes over; tested at ~5s of VIP downtime when Blocky stops on the holder |
| `tailscaled`     | yes            | Tailscale daemon container (pinned by digest; Renovate updates it)                                 |
| `vlans`          | yes            | 802.1q VLAN interfaces via NetworkManager                                                          |
| `avahi`          | yes            | Avahi mDNS reflector container (masks the host's own avahi-daemon)                                 |
| `github-runner`  | yes (`runners`) | Ephemeral just-in-time GitHub Actions runner for home-ops. A systemd service loops: mint a JIT config through the `rtrox-home-ops-runner` GitHub App, `docker run --rm` the pinned official runner image for exactly one job, repeat. The App key (`/etc/github-runner/app.json`) stays on the host; only the read-only Doppler CI tokens (`job.env`) enter job containers. Both files are root-only 0600. Jobs run on their own Docker network (`github-runner-jobs`), firewalled in `DOCKER-USER`: DNS, pve.rtrox.io:8006, mini's envoy-internal:443 (pocket-id; every app on that gateway) and HTTPS to the internet only, the rest of the private ranges rejected. Each job container is capped at 3h, and the loop backs off (up to 10 min) on GitHub failures |

Role variables and their defaults live in each role's `defaults/main.yaml`.

## Secrets

Secrets are in Doppler `hosts-at-home/prd` (set by hand) and `ansible/prd` (generated by the `dns` Terraform stack; rotate one with `tofu apply -replace=random_password.<name>` and re-run Ansible). The `task ansible:*` tasks run under `doppler run`, and the inventory or a role reads them with `lookup('env', ...)`. A play run without it fails on the empty value.

| Doppler key | Used by |
| --- | --- |
| `VALKEY_HOUSE_PASSWORD` (`ansible/prd`) | `valkey`, `blocky` on ns1 and ns2 |
| `VALKEY_APARTMENT_PASSWORD` (`ansible/prd`) | `valkey`, `blocky` on dns-a1; dns-a2 reads the same value as `BLOCKY_APARTMENT` in `k8s-at-home/min-ci` |
| `KEEPALIVED_HOUSE_PASSWORD` (`ansible/prd`) | `keepalived` (8 characters: all VRRP uses) |
| `GITHUB_RUNNER_APP`, `CI_DOPPLER_TF_READ`, `CI_DOPPLER_HOSTS_READ` | `github-runner` |

## Linting

`ansible/` is covered by the repo's yamllint config (`.github/lint/.yamllint.yaml`). It runs in pre-commit and CI.
