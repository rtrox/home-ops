# Moving the proxmox stack into home-ops

A one-time runbook for the owner. It moves the applied proxmox stack's state
from terraform-record's backend (B2, plaintext) to this stack's backend (R2,
encrypted), checks that the plan is only the intended change, then applies it.
Delete this file in the later cleanup PR that removes the old B2 key.

| | Old | New |
| --- | --- | --- |
| Code | `~/terraform-record-proxmox/proxmox/` (untracked) | `terraform/stacks/proxmox/` |
| Backend | B2 `rtrox-tf-state`, key `proxmox/proxmox.tfstate` | R2 `tofu-state`, key `stacks/proxmox/terraform.tfstate` |
| Encryption | none | pbkdf2 + aes_gcm, `enforced = true` |

The only intended changes are:

- `cloudflare_api_token.pve_acme` and `time_rotating.pve_acme_token` are
  created. The plugin's old token (Doppler `PVE_ACME_CLOUDFLARE_TOKEN`) no
  longer exists, so the next renewal, around Jan 20, fails without this.
- `proxmox_acme_dns_plugin.cloudflare` is updated in place (its `CF_Token`).

Nothing else changes. In particular, `proxmox_acme_certificate.pve` is not
replaced.

## Why the state moves in two steps

The new backend enforces encryption and the old state is plaintext. OpenTofu
reads plaintext state only when an `unencrypted` method is configured as a
`fallback`
([State and Plan Encryption: Pre-existing project](https://opentofu.org/docs/v1.13/language/state/encryption/#pre-existing-project)).
`enforced = true` forbids that, though. Every method in the chain is checked,
fallbacks included ("Unencrypted method is forbidden"), and neither
`TF_ENCRYPTION` nor an `*_override.tf` file can switch it off. The docs say both
are *merged* with the code
([Configuration](https://opentofu.org/docs/v1.13/language/state/encryption/#configuration)),
and the 1.13 merge ORs `enforced`
(`internal/encryption/config/config_merge.go`, `targets.go`). Both routes were
tried in a local sandbox and both fail. A `-backend-config` can't help either,
since it only sets backend arguments, not encryption.

So the plaintext-to-encrypted step runs in a scratch directory outside the
repo. That directory holds a hand-written copy of the stack's encryption block,
with the documented `unencrypted` fallback and without `enforced`:

1. **Scratch directory:** `tofu init -migrate-state` from the old B2 backend to
   a local file. The fallback reads the plaintext, and the file is written
   encrypted with the stack's key provider and method names (`pbkdf2.main`,
   `aes_gcm.main`). This also gives you a second, passphrase-encrypted backup.
2. **Stack directory:** a temporary `migrate_override.tf` points the backend at
   that local file. Then `task tf:init STACK=proxmox -- -migrate-state` copies
   it to R2. Encryption stays enforced throughout, because the source is already
   encrypted.

There are two reasons not to do it in one hop from B2 to R2. Both backends are
S3 and read `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from the same
environment, so one hop would mean writing one set of keys into a
`-backend-config`, which OpenTofu saves in plaintext in
`.terraform/terraform.tfstate`. The other is the enforcement problem above.
With two hops, no credential and no plaintext state ever touch the disk. The
fallback exists only in the scratch directory, which step 6 deletes, so the
repo never contains it.

## 0. Before you start

- You're on branch `feat/proxmox-stack` at the repo root. `mise install` is
  done, `doppler` is logged in, and `aws`, `age` and `jq` are on your PATH.
- Nothing else runs the old stack. Don't run `tofu` in
  `~/terraform-record-proxmox/proxmox` from here on.
- The B2 key `BACKBLAZE_TERRAFORM_STATE_KEY` is read from `tf-at-home/prd` below.
  If it lives in another config, change `-p`/`-c`.

Set these in the shell you'll use for every step:

```sh
cd ~/home-ops
REPO="$PWD"
STACK_DIR="$REPO/terraform/stacks/proxmox"
MIG="$HOME/tofu-migrate/proxmox"          # scratch, outside the repo
BACKUP_DIR="$HOME/tofu-backups"
AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
BACKUP="$BACKUP_DIR/proxmox-b2-$(date +%Y%m%dT%H%M%S).tfstate.age"   # one file per run
mkdir -p "$MIG" "$BACKUP_DIR" && chmod 700 "$MIG" "$BACKUP_DIR"
test ! -e "$MIG/proxmox.tfstate" || echo "STOP: $MIG/proxmox.tfstate already exists"
```

## 1. Back up the old state (age-encrypted, local)

This streams the B2 object straight into `age`, encrypted to your own age key,
so no plaintext copy is written. The B2 credentials exist only inside the
subshell.

```sh
(
  set -euo pipefail
  b2="$(doppler secrets get -p tf-at-home -c prd --plain BACKBLAZE_TERRAFORM_STATE_KEY)"
  export AWS_ACCESS_KEY_ID="$(jq -er .access_key <<<"$b2")"
  export AWS_SECRET_ACCESS_KEY="$(jq -er .secret_key <<<"$b2")"
  unset b2 AWS_PROFILE AWS_SESSION_TOKEN AWS_ENDPOINT_URL AWS_ENDPOINT_URL_S3
  export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
  aws s3 cp s3://rtrox-tf-state/proxmox/proxmox.tfstate - \
      --endpoint-url https://s3.us-west-004.backblazeb2.com --region us-west-004 \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP"
)
```

Check that it decrypts. This prints only the metadata and addresses:

```sh
age -d -i "$AGE_KEY" "$BACKUP" \
  | jq -r '"serial=\(.serial) lineage=\(.lineage) tofu=\(.terraform_version)",
           (.resources[] | (if .mode == "data" then "data." else "" end) + .type + "." + .name)'
```

The output should be `serial=2 … tofu=1.13.9` and exactly these three addresses:
`data.doppler_secrets.hosts`, `proxmox_acme_dns_plugin.cloudflare` and
`proxmox_acme_certificate.pve`. **Write down the lineage.** Anything else: stop.

## 2. Encrypt the state: B2 to a local file (scratch directory)

Write the scratch config. The key provider and method names must match
`_backend.tf` (`pbkdf2.main`, `aes_gcm.main`), because the encrypted file
records them.

```sh
cat > "$MIG/encryption.tf" <<'EOF'
# TEMPORARY: the documented unencrypted -> encrypted fallback, without
# enforced. Exists only for MIGRATION.md step 2; deleted in step 6.
terraform {
  encryption {
    method "unencrypted" "migrate" {}
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method = method.aes_gcm.main
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
variable "state_passphrase" {
  type      = string
  sensitive = true
}
EOF

cat > "$MIG/backend.tf" <<'EOF'
# The old terraform-record backend, verbatim.
terraform {
  backend "s3" {
    bucket = "rtrox-tf-state"
    key    = "proxmox/proxmox.tfstate"
    region = "us-east-1"
    endpoints = {
      s3 = "https://s3.us-west-004.backblazeb2.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
EOF
```

Initialise on B2, then switch the backend to a local file and migrate. The
warning "Unencrypted method configured" is expected here, and only here.

```sh
(
  set -euo pipefail
  b2="$(doppler secrets get -p tf-at-home -c prd --plain BACKBLAZE_TERRAFORM_STATE_KEY)"
  export AWS_ACCESS_KEY_ID="$(jq -er .access_key <<<"$b2")"
  export AWS_SECRET_ACCESS_KEY="$(jq -er .secret_key <<<"$b2")"
  unset b2 AWS_PROFILE AWS_SESSION_TOKEN AWS_ENDPOINT_URL AWS_ENDPOINT_URL_S3
  export TF_VAR_state_passphrase="$(doppler secrets get -p tf-at-home -c prd --plain TOFU_STATE_PASSPHRASE)"
  tofu() { mise -C "$REPO" exec -- tofu -chdir="$MIG" "$@"; }

  tofu init -input=false

  printf 'terraform {\n  backend "local" {\n    path = "proxmox.tfstate"\n  }\n}\n' > "$MIG/backend.tf"
  tofu init -migrate-state
)
```

At the prompt **"Do you want to copy existing state to the new backend?"**,
answer `yes`. Its description should say *"No existing state was found in the
newly configured "local" backend"*.

Check the result. The lineage must match step 1. The serial goes up as the
migration writes, so don't compare it.

```sh
jq -r '"lineage=\(.lineage) serial=\(.serial) encrypted=\(has("encrypted_data")) keys=\(.meta | keys | join(","))"' "$MIG/proxmox.tfstate"
```

Expect `encrypted=true keys=key_provider.pbkdf2.main` and your lineage.

## 3. Migrate: local file to R2 (stack directory)

```sh
cd "$STACK_DIR"
rm -rf .terraform            # local provider/backend cache only, never state
cat > migrate_override.tf <<EOF
# TEMPORARY (MIGRATION.md step 3): delete before the -migrate-state run.
terraform {
  backend "local" {
    path = "$MIG/proxmox.tfstate"
  }
}
EOF
cd "$REPO"
# Stop at the first failure: running -migrate-state without a recorded local
# backend would init R2 empty instead of copying the state.
task tf:init STACK=proxmox ALLOW_OVERRIDE=true \
  && [ "$(jq -r .backend.type "$STACK_DIR/.terraform/terraform.tfstate")" = local ] \
  && rm "$STACK_DIR/migrate_override.tf" \
  && task tf:init STACK=proxmox -- -migrate-state \
  || echo "STOPPED: fix the error above before going on (override left in place)"
```

The `jq` check must see `local` before the override is removed. If you see
`STOPPED`, nothing was copied to R2; fix the error and rerun this block.

At the prompt **"Do you want to copy existing state to the new backend?"**,
answer `yes` only if its description says *"No existing state was found in
the newly configured "s3" backend"*. If it says *"An existing non-empty state
already exists"*, answer `no` and stop: something is already at
`stacks/proxmox/terraform.tfstate` and needs a look first. While that prompt is
open, OpenTofu writes both states to temp files in plaintext, and it removes
them once you answer.

`*_override.tf` is git-ignored. `ls "$STACK_DIR"/*override*` must print nothing.

## 4. Verify: plan, both stacks

```sh
task tf:plan STACK=proxmox -- -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

This prints only resource headers and the summary, which is safe to paste
anywhere. The full plan shows the token as `(sensitive value)`. You should see
exactly:

```text
  # cloudflare_api_token.pve_acme will be created
  # proxmox_acme_dns_plugin.cloudflare will be updated in-place
  # time_rotating.pve_acme_token will be created
Plan: 2 to add, 1 to change, 0 to destroy.
```

In the full plan, the plugin's only changes are `data` (`CF_Token`) and
`digest -> (known after apply)` (computed, recalculated on any update), and
`proxmox_acme_certificate.pve` doesn't appear at all. An "Objects have changed
outside of OpenTofu" note on the certificate is fine if it's refresh-only (its
`not_after`/`fingerprint` change when Proxmox renews it). It isn't a planned
change.

**The old stack:** don't plan it, and never apply it. It now describes the same
objects as the new stack. Its plan fails anyway, on the deleted Doppler key
`PVE_ACME_CLOUDFLARE_TOKEN`, so it can't be applied by accident. Its B2 key
stays as it is (step 7).

### If the plan shows anything else

Don't apply. The B2 state and the real resources are untouched, and R2 holds a
faithful copy, so the fix is in code. Re-plan until the plan matches.

| You see | Meaning | Do |
| --- | --- | --- |
| plugin or certificate **will be created** | R2 state is empty or isn't this state | Re-check step 3's prompt answer and the lineage. Redo steps 2 and 3 from a fresh scratch dir (`rm -rf "$MIG" && mkdir -m 700 "$MIG"`). Step 3's prompt will now say "non-empty": answer `yes` to overwrite |
| certificate **must be replaced** / **will be updated** / **destroyed** | `acme.tf` differs from the old `acme.tf` | Diff the two (`node_name`, `account`, `domains`) and fix `acme.tf` (`prevent_destroy` already blocks a destroy) |
| plugin change beyond `data` and `digest` | attribute drift | Match the old `acme.tf`, or record why it's intended before going on |
| precondition "permission group was not found" | Cloudflare renamed `Zone Read`/`DNS Write` | Update `local.pve_acme_token_permissions` |
| 403 reading permission groups or creating the token | `CLOUDFLARE_TERRAFORM_TOKEN` lacks API Tokens access | Same token the old cloudflare stack uses for `cloudflare_api_token`, so check it hasn't changed |
| any `doppler_secret` | not expected, there are none | Stop |

## 5. Merge, then apply

Merge the PR once step 4 matches. Then apply from `main`, so the code you apply
is the reviewed code:

```sh
git switch main && git pull
task tf:plan STACK=proxmox        # the same 2 to add, 1 to change
task tf:apply STACK=proxmox       # review, then yes
task tf:plan STACK=proxmox        # must be "No changes."
```

Do this before about Jan 20, when Proxmox's renewal would otherwise fail. To
prove DNS-01 works now rather than in January, run this on the PVE host:
`pvenode acme cert renew --force 1`. The next plan then shows a refresh-only
note on the certificate and no changes.

### If an apply goes wrong

- **It fails partway** (for example, the token exists but the plugin update
  failed): nothing is worse than today, since the plugin still has the dead
  token. Fix the cause and apply again.
- **The token is wrong or unwanted:** delete it in the Cloudflare dashboard (or
  `task tf:apply` with it fixed). The next plan recreates it and updates the
  plugin.
- **The certificate:** `prevent_destroy` stops any plan that would destroy it.
  If the host's certificate breaks anyway, `pvenode acme cert order --force 1`
  on the host reissues it, and a plan afterwards only refreshes it.
- **Back to the old stack:** the B2 state is untouched, but the old code can't
  plan (its Doppler key is gone) and its token is dead, so there's nothing
  working to roll back to. Fix forward in this stack. The age backup from
  step 1 is the last resort; restoring it is a manual `tofu state push` by the
  owner.

## 6. Remove the temporary fallback

The fallback and the encrypted intermediate exist only in the scratch
directory:

```sh
ls "$STACK_DIR"/*override* 2>/dev/null && echo "STOP: override file still present"
rm -rf "$MIG"
git -C "$REPO" status --short terraform/   # expect nothing
```

Keep the age backup in `$BACKUP_DIR` until step 7's cleanup.

## 7. Leave the old B2 key alone

`rtrox-tf-state/proxmox/proxmox.tfstate` stays in B2 for now, as a second
copy. A later cleanup, once this stack has applied cleanly, deletes that key,
`~/terraform-record-proxmox/proxmox/`, the age backup and this file.
