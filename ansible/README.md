# Ansible

Configuration for the non-Kubernetes machines: the Raspberry Pi / Orange Pi boxes that run DNS (`ns1`, `ns2`) and the mDNS reflector (`avahi`). Everything here runs as Docker containers managed by systemd units, so each role mostly templates a `.service` file and enables it.

## Hosts

| Host             | Address     | Group   | Notes                                        |
| ---------------- | ----------- | ------- | -------------------------------------------- |
| `ns1.rtrox.io`   | 172.30.99.1 | `dns`   | Blocky + keepalived `MASTER`, Tailscale      |
| `ns2.rtrox.io`   | 172.30.99.2 | `dns`   | Blocky + keepalived `BACKUP`, Tailscale      |
| `avahi.rtrox.io` | 172.30.99.3 | `avahi` | VLAN interfaces (200, 300) + Avahi reflector |

## Setup

Two files are **local only** (gitignored) and must exist before running anything:

- **`inventory.yaml`**: the hosts above, plus the SSH user. The username is treated as secret: it lives only here, never in committed files.

  ```yaml
  all:
    vars:
      ansible_user: <ssh-user>

  dns:
    hosts:
      ns1.rtrox.io:
        ansible_host: 172.30.99.1
        keepalived_state: MASTER
      ns2.rtrox.io:
        ansible_host: 172.30.99.2
        keepalived_state: BACKUP

  avahi:
    hosts:
      avahi.rtrox.io:
        ansible_host: 172.30.99.3
        vlan_interfaces:
          - interface: "eth0"
            vlan_id: 200
          - interface: "eth0"
            vlan_id: 300
  ```

- **`.ansible-vault-pass`**: the Ansible Vault password, mode `600`.

The `geerlingguy.docker` role is installed from Galaxy, not vendored:

```sh
ansible-galaxy role install geerlingguy.docker
```

SSH access is by key only (`secure-ssh` disables password auth), and the `ansible_user` needs passwordless sudo, since every play runs with `become: true`.

## Running

```sh
cd ansible

# Dry run one host, showing file diffs
ansible-playbook -i inventory.yaml site.yaml -l <host> \
  --vault-password-file .ansible-vault-pass --check --diff

# Apply
ansible-playbook -i inventory.yaml site.yaml -l <host> \
  --vault-password-file .ansible-vault-pass
```

Apply one DNS server at a time. Restarting Docker (any `daemon.json` change does it) briefly takes DNS down on that host, and keepalived only covers for it if the other one is healthy.

## Playbook layout (`site.yaml`)

1. **All hosts**: `auto-upgrade`, `secure-ssh`, `geerlingguy.docker`, `raspi-monitor`, `node-exporter`, then hostname, UTC timezone and common packages.
2. **`dns`**: `blocky`, `keepalived`, `tailscaled`. Loads `blocky_secrets.yaml` and `keepalived_secrets.yaml`.
3. **`avahi`**: `vlans`, `avahi`.

## Roles

| Role             | In `site.yaml` | What it does                                                                                       |
| ---------------- | -------------- | -------------------------------------------------------------------------------------------------- |
| `auto-upgrade`   | yes            | `unattended-upgrades` (Docker included), automatic reboot at 09:00 UTC                             |
| `secure-ssh`     | yes            | Syncs `authorized_keys` from `github.com/<user>.keys` and/or `ssh_public_keys`, then disables password auth (refuses to if no keys ended up in the file) |
| `raspi-monitor`  | yes            | Enables I2C (Raspberry Pi or Orange Pi) and runs the OLED status display container                 |
| `node-exporter`  | yes            | Prometheus node-exporter container                                                                 |
| `blocky`         | yes            | Blocky DNS container, frees port 53 from systemd-resolved, pins `/etc/resolv.conf`                 |
| `keepalived`     | yes            | VRRP virtual IP shared between ns1/ns2                                                             |
| `tailscaled`     | yes            | Tailscale daemon container                                                                         |
| `vlans`          | yes            | 802.1q VLAN interfaces via NetworkManager                                                          |
| `avahi`          | yes            | Avahi mDNS reflector container (masks the host's own avahi-daemon)                                 |
| `adguardhome`    | no             | AdGuard Home container (superseded by Blocky)                                                      |
| `dns-over-https` | no             | cloudflared DoH proxy                                                                              |
| `coredns`        | no             | Corefile template only, no tasks                                                                   |

Role variables and their defaults live in each role's `defaults/main.yaml`.

## Secrets

All secrets files are Ansible Vault-encrypted, named `<thing>_secrets.yaml`:

| File                      | Used by                              |
| ------------------------- | ------------------------------------ |
| `blocky_secrets.yaml`     | `blocky` (Postgres/Redis addresses)  |
| `keepalived_secrets.yaml` | `keepalived` (VIP, auth password)    |
| `adguard_secrets.yaml`    | `adguardhome` (not currently loaded) |

```sh
ansible-vault edit --vault-password-file .ansible-vault-pass blocky_secrets.yaml
```

Never commit a decrypted secrets file. Check that the first line is `$ANSIBLE_VAULT;1.1;AES256` before staging.
