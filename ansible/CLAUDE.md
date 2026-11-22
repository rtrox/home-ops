# Ansible: agent notes

See [README.md](README.md) for hosts, roles and how to run things. This file holds the non-obvious rules.

- **File naming**: every YAML file is `.yaml` (never `.yml`), and every vault file is `<thing>_secrets.yaml`. The one exception is files deployed to hosts whose name the app dictates (e.g. `/etc/blocky/config.yaml`).
- **Never print secrets**: don't `cat`/`view` vault files or `.ansible-vault-pass`. To check encryption state, look only at the first line (`$ANSIBLE_VAULT;1.1;AES256`). Re-encrypt any decrypted file before committing.
- **Users**: the default `ansible_user` is `rtrox` (committed in `inventory/group_vars/all.yaml`, also the Proxmox VMs' cloud-init user and the Proxmox admin). The Pis are a temporary exception: `group_vars/pis.yaml` reads their original user from Doppler `ANSIBLE_SSH_USER` (via `doppler run -p hosts-at-home -c prd --` in the Taskfile), and that value is treated as secret, never written into a committed file. Always run plays via `task ansible:*`. The only local-only file is `.ansible-vault-pass`. Hostnames and IPs are fine to document. Plays targeting `all` use `all:!unmanaged:!vms` until the VMs get roles.
- **SSH is key-only on everything we build**: no password and no keyboard-interactive authentication (`secure-ssh` and the Proxmox role's `sshd-hardening.conf`). New hosts get keys through cloud-init or the role, never a password.
- **Privilege**: plays use `become: true`, and the `ansible_user` has passwordless sudo. Paths under the user's home use `/home/{{ ansible_user }}`, so they stay correct under become.
- **Check mode**: always dry-run first (`task ansible:check HOST=<host>`, which wraps `--check --diff`). A read-only task whose result later tasks depend on (`uri` fetches, `shell` probes) needs `check_mode: false`, or it's skipped and the dependent task breaks. Test a skipped registered result with `is not skipped`, not `is defined` (a skipped result is still defined).
- **Handlers**: shared handler files go in with `import_tasks` (static), not `include_tasks`. Handlers inside a dynamic include, including any `listen:` handlers, don't exist until the include itself runs, so their notifies fail.
- **SD cards / logs in RAM**: ns1 runs off an SD card. The journal is volatile (`roles/journald`) and Docker uses the `journald` log driver, so no logs are written to disk. Don't reintroduce disk logging: no `json-file` driver, no persistent journal, no log files under bind mounts. Anything worth keeping should be shipped off the host.
- **DNS hosts**: apply ns1 and ns2 one at a time. A Docker restart takes DNS down on that box.
- **Validate**: `task ansible:syntax`. Prefer the `ansible:*` tasks over raw `ansible-playbook`: they bake in the inventory, vault file and `--forks 1`.
- **Pre-commit**: yamllint covers `ansible/`, and the `ansible-vault-encrypted` hook rejects any unencrypted `*_secrets.yaml`. Don't bypass either with `--no-verify`.
