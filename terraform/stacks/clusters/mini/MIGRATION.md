# Moving mini's Terraform into home-ops (migration phase 2, P2-3)

A one-time runbook for the owner. It moves what mini needs from outside the
cluster out of terraform-record's `cloudflare` and `backblaze` stacks into
this stack, and the backups of the root of trust into `foundation`
([foundation's MIGRATION.md](../../foundation/MIGRATION.md), "P2-3"). Delete
this file, `imports.tf` and the two preconditions marked "P2-3 move only" in
the cleanup PR (step 9).

Applied from the laptop. The stack has no tags yet; `ci-apply` waits for the
zero-diff gate and for CI credentials that can plan it ([CI](#ci)).

## What moves, and how

| Object | To | Method |
| --- | --- | --- |
| `mini.rtrox.io` A records ×3 (`rtrox_io_host["mini_0".."mini_2"]`) | clusters/mini `cloudflare_dns_record.api[<node>]`, addresses from `inventory/hosts.yaml` | import by ID |
| Tunnel `mini_external_ingress` | `cloudflare_zero_trust_tunnel_cloudflared.mini` (`ignore_changes = [tunnel_secret, config_src]`, `prevent_destroy`) | import (ID found by name) |
| `random_id.argo_secret_mini` | `random_bytes.tunnel_secret` (same 35 bytes) | import by value |
| `CLOUDFLARED_CREDENTIALS` | `doppler_secret.cloudflared_credentials` | import, **unchanged** |
| external-dns and cert-manager tokens | new `k8s-mini-rtrox-io-{external-dns,certmanager}-<date>` (rtrox.io only, 90-day reissue, 180-day expiry) | rotate |
| `EXTERNALDNS_CLOUDFLARE_TOKEN`, `CERTMANAGER_CLOUDFLARE_TOKEN` | `doppler_secret.external_dns_token`, `.cert_manager_token` | import, updated to the new tokens |
| Bucket `k8s-rtrox-io-volsync-store` (4 lifecycle rules, unchanged) | `module.volsync_store` | import |
| Its key `k8s-mini-rtrox-io-volsync-store` | new key, same name and capabilities | rotate |
| `random_password.volsync_restic_password` | `random_password.volsync_restic` | import by value |
| `VOLSYNC_BACKBLAZE_BUCKET` | `doppler_secret.volsync_bucket` | import, updated to the new key; **same restic password** |
| Bucket `k8s-mini-rtrox-io-cnpg-offsite` (Object Lock governance 45 days) | `module.cnpg_offsite_store` | import |
| Its keys `k8s-mini-rtrox-io-cnpg-offsite` (writer) and `-restore` (read-only, for DR) | new keys, same names and capabilities | rotate |
| `CNPG_OFFSITE_BACKBLAZE_BUCKET`, `CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET` | `doppler_secret.cnpg_offsite_bucket`, `.cnpg_offsite_restore_bucket` | import, updated to the new keys |
| R2 copy token `tofu-state-copy`, `TOFU_STATE_R2_SOURCE` | foundation: new `tofu-state-copy-mini-readonly`; secret imported and updated | rotate / import |
| Bucket `rtrox-tofu-state-history` (Object Lock governance 90 days), its key, `TOFU_STATE_HISTORY_BACKBLAZE_BUCKET` | foundation | import / rotate / import |
| Bucket `k8s-mini-rtrox-io-secrets-backup` (Object Lock governance 90 days), its key, `SECRETS_BACKUP_BACKBLAZE_BUCKET` | foundation | import / rotate / import |
| `CLOUDFLARE_MINI_TOKEN` (this stack's provider token) | foundation, `tf-at-home` `prd`, `ci-apply` (and `ci`: the read-only CI token) | create |

Counts: clusters/mini imports 14 and creates 7; foundation imports 5 and
creates 8; terraform-record forgets 9 (cloudflare) and 10 (backblaze), and
later destroys 3 and 5 old credentials.

Not moving: MinIO (terraform-record `minio`; phase 4 replaces it with
Garage), the TrueNAS bucket and tokens.

### By-value imports

A `random_*` resource is imported by its value, and these two are secrets: the
tunnel secret (with the tunnel ID, it runs a connector for the tunnel) and the
restic password (it opens every volsync backup). So:

- **They are never committed and never in `tf-at-home`** (`prd`, `ci` or
  `ci-apply`). You read them from where they already live,
  `k8s-at-home/min`, into `TF_VAR_import_*` for this stack's runs during the
  move only, with the `mini_env` function below.
- **A plan without them fails.** Each random resource has a precondition
  ("P2-3 move only") that stops any plan of this stack where its value isn't
  supplied, so no plan can quietly create a new secret instead of importing
  the old one. After the move, `prevent_destroy` and `ignore_changes = all`
  keep both from ever being replaced or changed; the cleanup PR removes the
  preconditions.
- **The import prints them**, and tofu can't be told otherwise: an import ID
  can't be sensitive, so it appears in `Preparing import... [id=...]`,
  `(imported from "...")` and `Importing... [id=...]`. Run this stack's plans
  and applies through `redact` until the cleanup PR, and apply the reviewed
  plan file, never an interactive `apply`. After the import nothing prints
  either one: `random_bytes` has no `id` (terraform-record's `random_id` had
  the secret as its id, so every one of its plans printed it, in TFC's run logs
  too), and `random_password`'s is `none`.

Define these in the shell you run the steps from (`mini_env` reads only the
two fields, `redact` blanks every `[id=...]` and import source):

```sh
mini_env() {
  local c v
  c=$(doppler secrets get CLOUDFLARED_CREDENTIALS -p k8s-at-home -c min --plain) || return 1
  TF_VAR_import_tunnel_secret=$(jq -er .TunnelSecret <<<"$c" 2>/dev/null) || { echo "no TunnelSecret" >&2; return 1; }
  v=$(doppler secrets get VOLSYNC_BACKBLAZE_BUCKET -p k8s-at-home -c min --plain) || return 1
  TF_VAR_import_restic_password=$(jq -er .restic_password <<<"$v" 2>/dev/null) || { echo "no restic_password" >&2; return 1; }
  export TF_VAR_import_tunnel_secret TF_VAR_import_restic_password
}
redact() { sed -E 's/\[id=[^]]*\]/[id=…]/g; s/^( *# \(imported from ).*$/\1…)/'; }
```

Use them in a subshell, so the variables are gone when it exits:
`( set -euo pipefail; mini_env; task tf:plan STACK=clusters/mini -- -no-color 2>&1 | redact )`.
The variables' validations reject anything that isn't 35 bytes of base64 or
32 letters and digits, without printing it.

## 0. Preconditions

- **TFC versions.** Both workspaces must run Terraform 1.7 or later (removed
  blocks). Prints the version and execution mode only:

  ```sh
  TFC=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
  for w in arpa-home-cloudflare arpa-home-backblaze; do
    curl -fsS -H "Authorization: Bearer $TFC" \
      "https://app.terraform.io/api/v2/organizations/rtrox/workspaces/$w" \
      | jq -r --arg w "$w" '.data.attributes | "\($w) terraform-version=\(."terraform-version") execution-mode=\(."execution-mode")"'
  done
  unset TFC
  ```

  `backblaze` still says `required_version = ">= 1.3.0"`; if its workspace is
  below 1.7, raise it in the workspace settings first.
- **Baseline: everything plans clean.** `env -u TF_VAR_doppler_token tofu
  -chdir=cloudflare plan` and `-chdir=backblaze plan` on terraform-record
  `main`, and `task tf:plan STACK=foundation` here, each `No changes.`
  Anything else: resolve it first, or it gets mixed up with the move.
- **CI won't plan this stack** ([CI](#ci)). Decide how before merging the
  clusters/mini PR, or the nightly `terraform-drift` fails from then on.
- **Freeze.** From here to step 8: no applies to terraform-record `cloudflare`
  or `backblaze`, `foundation` or this stack except the ones below, and no
  changes to `cloudflared`, `external-dns`, `cert-manager`, volsync,
  `cnpg-offsite`, `doppler-export` or `tofu-state-copy` in the cluster.
- **Don't use `task volsync:restic-env`** while checking backups: it prints
  the restic password and keys (`.taskfiles/volsync/Taskfile.yaml`, out of
  scope here). `task volsync:snapshots` doesn't print them.
- **Back up the secrets that change**, age-encrypted, never printed. This is
  the rollback until step 8:

  ```sh
  BACKUP_DIR="$HOME/tofu-backups"; mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
  STAMP=$(date +%Y%m%dT%H%M%S)
  doppler secrets download -p k8s-at-home -c min --no-file --format json \
    | jq '{EXTERNALDNS_CLOUDFLARE_TOKEN, CERTMANAGER_CLOUDFLARE_TOKEN, CLOUDFLARED_CREDENTIALS,
           VOLSYNC_BACKBLAZE_BUCKET, CNPG_OFFSITE_BACKBLAZE_BUCKET, CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET,
           TOFU_STATE_R2_SOURCE, TOFU_STATE_HISTORY_BACKBLAZE_BUCKET, SECRETS_BACKUP_BACKBLAZE_BUCKET}' \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP_DIR/mini-min-$STAMP.json.age"
  # Check: key names only, and none null.
  age -d -i "$AGE_KEY" "$BACKUP_DIR/mini-min-$STAMP.json.age" | jq -r 'to_entries[] | "\(.key) set=\(.value != null)"'
  ```

  Expect nine names, all `set=true`. Write down `$STAMP`. The checks below
  compare against this backup with:

  ```sh
  # unchanged KEY [FIELD]: is KEY (or its JSON FIELD) the same in Doppler as in
  # the backup? Prints yes/NO only.
  unchanged() {
    local f=${2:-}
    a=$(age -d -i "$AGE_KEY" "$BACKUP_DIR/mini-min-$STAMP.json.age" | jq -j --arg k "$1" --arg f "$f" 'if $f == "" then .[$k] else (.[$k] | fromjson | .[$f]) end' | sha256sum)
    b=$(doppler secrets get "$1" -p k8s-at-home -c min --plain | jq -Rsj --arg f "$f" 'rtrimstr("\n") | if $f == "" then . else (fromjson | .[$f]) end' | sha256sum)
    [ "$a" = "$b" ] && echo "$1${f:+.$f} unchanged: yes" || echo "$1${f:+.$f} unchanged: NO"
  }
  ```

## 1. Foundation: the mini token only

Merge the foundation PR, then create only `CLOUDFLARE_MINI_TOKEN` (this
stack's plans need it). `-target` leaves the imports alone:

```sh
git switch main && git pull
task tf:apply STACK=foundation -- -target=doppler_secret.mini_token_prd -target=doppler_secret.mini_token_ci_apply -target=doppler_secret.mini_token_ci
```

Expect `Plan: 0 to import, 5 to add, 0 to change, 0 to destroy.`:
`time_rotating.mini_token`, `cloudflare_api_token.mini` and the three
`doppler_secret.mini_token_*`. A targeting warning is expected. A 403 creating
the token means `CLOUDFLARE_TERRAFORM_TOKEN` can't grant one of its groups;
a precondition about a permission group means a name in
`local.mini_token_permissions` (foundation's `mini_token.tf`) doesn't exist.

## 2. Plan both new stacks, before anything is forgotten

Plans change nothing, so check both now, while terraform-record still manages
everything. Foundation (from `main`, see its MIGRATION.md for the list):

```sh
task tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
# Plan: 5 to import, 3 to add, 3 to change, 0 to destroy.
```

This stack, from the clusters/mini PR's branch:

```sh
git switch <the clusters/mini PR branch> && git pull
task tf:init STACK=clusters/mini
( set -euo pipefail; mini_env
  task tf:plan STACK=clusters/mini -- -no-color 2>&1 | redact | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):' )
```

Expect `Plan: 14 to import, 7 to add, 5 to change, 0 to destroy.`

- **14 imports**: `cloudflare_dns_record.api` ×3 (`node01`..`node03`),
  `cloudflare_zero_trust_tunnel_cloudflared.mini`, `random_bytes.tunnel_secret`,
  `random_password.volsync_restic`, `module.volsync_store.b2_bucket.this`,
  `module.cnpg_offsite_store.b2_bucket.this`, and six `doppler_secret`s. These
  show `will be imported` and nothing else: the records, tunnel, buckets,
  randoms and `doppler_secret.cloudflared_credentials`.
- **7 creates**: `module.external_dns_token` and `module.cert_manager_token`,
  each a `time_rotating.this` and a `cloudflare_api_token.this`;
  `module.volsync_store.b2_application_key.this["k8s-mini-rtrox-io-volsync-store"]`,
  and `module.cnpg_offsite_store.b2_application_key.this` for
  `k8s-mini-rtrox-io-cnpg-offsite` and `-restore`.
- **5 updates**, each also imported, `value` only (`(sensitive value)`):
  `doppler_secret.external_dns_token`, `.cert_manager_token`,
  `.volsync_bucket`, `.cnpg_offsite_bucket`, `.cnpg_offsite_restore_bucket`.
  That's the rotation. `volsync_bucket`'s new value keeps the imported restic
  password; step 5 checks it.

### If the plan shows anything else

Don't apply. Fix the code and re-plan.

| You see | Meaning | Do |
| --- | --- | --- |
| `Resource precondition failed` ... `import_tunnel_secret` / `import_restic_password` | `mini_env` didn't run in that subshell | Run the plan as shown |
| `random_bytes.tunnel_secret` or `random_password.volsync_restic` **will be created** | the import didn't happen | Never apply that. Check `mini_env` and the import blocks |
| `doppler_secret.cloudflared_credentials` **updated** | the JSON this stack builds differs from what's in Doppler (account, tunnel name or ID, secret, or key order) | Compare the backup's `CLOUDFLARED_CREDENTIALS` field by field with `unchanged CLOUDFLARED_CREDENTIALS <Field>` (step 0's function); fix `tunnel.tf` |
| a `doppler_secret` update showing `visibility` or `value_type` too | the secret isn't `masked`/`string` | Set that attribute on the resource to the live value; only `value` may change |
| a bucket updated, only reordering `lifecycle_rules` | B2 returned the rules in another order | Reorder them in the code to match the plan's current order; re-plan |
| a bucket updated otherwise, or **must be replaced** (`prevent_destroy` error) | the code differs from the bucket (rules, file lock, type) | Match the code to the plan's current values; the bucket's settings must not change in this move |
| the tunnel updated or replaced | `name` or `account_id` differ | Match `tunnel.tf`; never apply a tunnel replacement |
| a record updated | content, comment, proxied or TTL differ | Match `api_records.tf` or `inventory/hosts.yaml` to the live record |
| `failed to find exactly one result` (tunnel lookup) | no live tunnel, or two, named `mini_external_ingress` | Check the dashboard; the import needs exactly one |
| 403 on the tunnel or tokens | `CLOUDFLARE_MINI_TOKEN` lacks a group | Add `Cloudflare Tunnel Read` or `API Tokens Read` to foundation's `mini_token.tf` (Write may not include Read for these); apply foundation again |
| **anything destroyed** | not intended | Stop |

## 3. Forget, in terraform-record (TFC)

Apply rtrox/terraform-record#66 (both workspaces). Remote TFC runs must never get
your Doppler CLI token, so unset it. On the PR branch first, then merged:

```sh
cd ~/terraform-record
for s in cloudflare backblaze; do
  env -u TF_VAR_doppler_token tofu -chdir=$s plan -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
done
```

`cloudflare`, 3 moved and 9 forgotten:

```text
  # cloudflare_dns_record.rtrox_io_host["mini_0"] has moved to cloudflare_dns_record.rtrox_io_host_moved_to_clusters_mini["mini_0"]
  ... (mini_1, mini_2)
  # cloudflare_dns_record.rtrox_io_host_moved_to_clusters_mini["mini_0"] will be removed from the state but will not be destroyed
  ... (mini_1, mini_2)
  # cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel_mini ...
  # doppler_secret.argo_tunnel_mini_secret ...
  # doppler_secret.cf_api_token_mini_certmanager ...
  # doppler_secret.cf_api_token_mini_external_dns ...
  # doppler_secret.r2_state_copy_mini ...
  # random_id.argo_secret_mini ...
Plan: 0 to add, 0 to change, 0 to destroy, 9 to forget.
```

`backblaze`, 5 moved and 10 forgotten:

```text
  # module.bb_bucket_k8s_rtrox_io_volsync_store.b2_application_key.keys["k8s-mini-rtrox-io-volsync-store"] has moved to b2_application_key.old_volsync_store
  ... (old_mini_cnpg_offsite, old_mini_cnpg_offsite_restore, old_tofu_state_history, old_mini_secrets_backup)
  # module.bb_bucket_k8s_rtrox_io_volsync_store.b2_bucket.bucket will be removed from the state but will not be destroyed
  ... (the cnpg-offsite, tofu-state-history and secrets-backup buckets)
  # random_password.volsync_restic_password ...
  # doppler_secret.volsync_key_mini ... (and cnpg_offsite_key_mini, cnpg_offsite_restore_key_mini,
  #   tofu_state_history_key_mini, secrets_backup_key_mini)
Plan: 0 to add, 0 to change, 0 to destroy, 10 to forget.
```

A moved key that shows an update or replacement means its arguments in
`backblaze/moved_to_home_ops.tf` differ from the old module's: don't apply
(a replaced key would break its consumer before the new one exists). The
old tokens and keys must not appear at all except as moves. Then merge and,
from `main`, apply each and re-plan to `No changes.`:

```sh
git switch main && git pull
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token tofu -chdir=$s apply; done   # the same counts; yes
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token tofu -chdir=$s plan -no-color | grep -E '^Plan:|^No changes'; done
```

Nothing in Cloudflare, B2 or Doppler changes; only TFC's state.

## 4. Apply foundation

```sh
cd ~/home-ops && git switch main && git pull
task tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^Plan:|^No changes'   # 5 to import, 3 to add, 3 to change
task tf:apply STACK=foundation                                                  # review, then yes
```

## 5. Merge, then apply this stack

Merge the clusters/mini PR, then from `main`. Plan to a file, review the
redacted plan, and apply that file:

```sh
git switch main && git pull
PLAN="$HOME/tofu-backups/clusters-mini-$STAMP.tfplan"
( set -euo pipefail; mini_env
  task tf:plan STACK=clusters/mini -- -no-color -out="$PLAN" 2>&1 | redact )   # 14 to import, 7 to add, 5 to change
( set -euo pipefail; task tf:apply STACK=clusters/mini -- -no-color "$PLAN" 2>&1 | redact )
rm -f "$PLAN"
```

The plan file is encrypted (state and plan encryption are enforced) but holds
the two values; it's deleted once applied. Applying a saved plan doesn't ask
for confirmation: the review is the redacted plan.

Doppler now holds the new tokens and keys. The old ones stay valid until step
8, so every consumer keeps working whichever value it has.

## 6. Check every consumer

Times are Pacific (the CronJobs run in UTC). ExternalSecrets refresh hourly:
a cluster Secret has the new value within the hour, or at once with
`kubectl annotate externalsecret -n <ns> <name> force-sync=$(date +%s) --overwrite`.

```sh
# k8s_vs_doppler NS SECRET FIELD KEY [JQ]: does the cluster Secret's FIELD equal
# Doppler's KEY (or JQ of it)? Prints yes/NO only.
k8s_vs_doppler() {
  a=$(kubectl get secret -n "$1" "$2" -o json | jq -j --arg f "$3" '.data[$f] | @base64d' | sha256sum)
  b=$(doppler secrets get "$4" -p k8s-at-home -c min --plain | jq -Rsj --arg q "${5:-}" 'rtrimstr("\n") | if $q == "" then . else (fromjson | getpath($q | split("."))) end' | sha256sum)
  [ "$a" = "$b" ] && echo "$1/$2 $3 = $4${5:+.$5}: yes" || echo "$1/$2 $3 = $4${5:+.$5}: NO"
}
# cf_verify KEY: is the Cloudflare token in KEY active? Prints the status only.
cf_verify() {
  local t; t=$(doppler secrets get "$1" -p k8s-at-home -c min --plain)
  echo "$1: $(curl -fsS -K - https://api.cloudflare.com/client/v4/user/tokens/verify <<<"header = \"Authorization: Bearer $t\"" | jq -r .result.status)"
}
```

1. **The values that must not change**, against the step 0 backup; all `yes`:

   ```sh
   unchanged CLOUDFLARED_CREDENTIALS
   unchanged VOLSYNC_BACKBLAZE_BUCKET restic_password
   ```

   A `NO` on either: restore it now ([rollback](#if-an-apply-goes-wrong)).
2. **external-dns** (Reloader restarts it when its Secret changes):
   `cf_verify EXTERNALDNS_CLOUDFLARE_TOKEN` says `active`;
   `k8s_vs_doppler network externaldns-cloudflare-token cloudflare-token EXTERNALDNS_CLOUDFLARE_TOKEN`
   says `yes`; its pod is younger than the sync; and
   `kubectl -n network logs deploy/external-dns --since=15m | grep -ciE '403|unauthorized|authentication'`
   prints `0`.
3. **cert-manager** (reads the Secret at each DNS-01 challenge, no restart):
   `cf_verify CERTMANAGER_CLOUDFLARE_TOKEN` says `active`;
   `k8s_vs_doppler cert-manager cloudflare-token-secret cloudflare-token CERTMANAGER_CLOUDFLARE_TOKEN`
   says `yes`; `kubectl get certificates -A` all `READY True` and
   `kubectl get challenges -A` empty. The next renewal is the end-to-end test;
   to test now, renew one certificate (`cmctl renew -n <ns> <cert>`) and watch
   its challenge clear.
4. **cloudflared**: nothing changed (check 1). Its pods are Ready, the tunnel
   is HEALTHY in the Zero Trust dashboard, and an external hostname answers.
5. **volsync**, every app's B2 mover:
   `k8s_vs_doppler <ns> <app>-volsync-b2-secret AWS_ACCESS_KEY_ID VOLSYNC_BACKBLAZE_BUCKET application_key_id`
   says `yes` for one app (they share the key). `task volsync:snapshots
   APP=<app> NAMESPACE=<ns> BACKEND=b2` lists snapshots (the new key and the
   unchanged password open the repository). After the next run (4:00 pm),
   every B2 source succeeded since the apply:

   ```sh
   kubectl get replicationsource -A -o json | jq -r '.items[] | select(.metadata.name | endswith("-b2"))
     | "\(.metadata.namespace)/\(.metadata.name) \(.status.lastSyncTime) \(.status.latestMoverStatus.result)"'
   ```

6. **cnpg-offsite** (6:00 pm): the run succeeds and its healthchecks.io check
   gets a success ping. To run it now:
   `kubectl create job -n database --from=cronjob/cnpg-offsite cnpg-offsite-p2-3`.
7. **The CNPG restore key** (no reader in the cluster): it lists the bucket.
   With rclone installed:

   ```sh
   ( r=$(doppler secrets get CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET -p k8s-at-home -c min --plain)
     export RCLONE_CONFIG_R_TYPE=b2 RCLONE_CONFIG_R_ACCOUNT="$(jq -r .application_key_id <<<"$r")" RCLONE_CONFIG_R_KEY="$(jq -r .application_key <<<"$r")"
     b=$(jq -r .bucket <<<"$r"); unset r
     rclone lsf --max-depth 1 "r:$b" >/dev/null && echo "restore key lists: yes" || echo "restore key lists: NO" )
   ```

8. **tofu-state-copy** (8:00 pm) and **doppler-export** (Saturdays, 7:00 pm):
   each run succeeds and pings healthchecks.io. To run them now:
   `kubectl create job -n terraform --from=cronjob/tofu-state-copy tofu-state-copy-p2-3`,
   `kubectl create job -n security --from=cronjob/doppler-export doppler-export-p2-3`.
9. **Both stacks here:** `task tf:plan STACK=foundation` says `No changes.`;
   this stack too, through `mini_env` and `redact` (step 2's command).

## 7. Wait

Leave the old credentials for one full nightly cycle (volsync, cnpg-offsite,
tofu-state-copy) and one doppler-export run (or the manual jobs above), so a
consumer that reads at a different time also proves it's healthy. Until step
8 everything is reversible from the step 0 backup.

## 8. Delete the old credentials

Apply rtrox/terraform-record#67 (procedure step 4). Plan on its branch,
then merged, from `main`:

```text
cloudflare:
  # module.cf_api_token_mini_certmanager.cloudflare_api_token.token will be destroyed
  # module.cf_api_token_mini_external_dns.cloudflare_api_token.token will be destroyed
  # cloudflare_api_token.r2_state_copy will be destroyed
Plan: 0 to add, 0 to change, 3 to destroy.
backblaze:
  # b2_application_key.old_mini_cnpg_offsite will be destroyed
  # b2_application_key.old_mini_cnpg_offsite_restore will be destroyed
  # b2_application_key.old_mini_secrets_backup will be destroyed
  # b2_application_key.old_tofu_state_history will be destroyed
  # b2_application_key.old_volsync_store will be destroyed
Plan: 0 to add, 0 to change, 5 to destroy.
```

Anything else: don't apply. Afterwards re-run step 6's checks 2, 3, 5 (the
`snapshots` task), 7, and the next nightly runs: everything still reads with
the new credentials.

## 9. Zero-diff gate, cleanup, then CI

All four must say `No changes.`:

```sh
task tf:plan STACK=foundation
( set -euo pipefail; mini_env; task tf:plan STACK=clusters/mini -- -no-color 2>&1 | redact | grep -E '^Plan:|^No changes' )
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token tofu -chdir="$HOME/terraform-record/$s" plan -no-color | grep -E '^Plan:|^No changes'; done
```

The freeze ends here. Then:

1. **Cleanup PR**: delete `imports.tf`, this file and the two "P2-3 move
   only" preconditions here, and foundation's P2-3 imports. Its plan says
   `No changes.` *without* `mini_env`, which proves the preconditions are
   gone and nothing wants a new secret. From then on, plans of this stack
   print neither value. terraform-record's removed blocks, its `random`
   requirement and `doppler.min_write` aliases go in its own cleanup.
2. **CI credentials** ([CI](#ci)), then the PR that tags this stack
   `ci-apply`.

Delete the step 0 backup once the gate has held for a week.

## If an apply goes wrong

- **Step 1** only created a token nothing reads yet. Nothing to undo.
- **Step 3 (forget) misbehaves:** forgetting edits only TFC's state; nothing
  in Cloudflare, B2 or Doppler changed. Don't apply foundation or this stack.
  Either carry on (steps 4 and 5 adopt everything anyway), or revert the PR
  and adopt the objects back in terraform-record with `import` blocks (the
  same IDs as `imports.tf` here; the random_id by value from `TunnelSecret`
  converted to base64url: `tr '+/' '-_' | tr -d '='`). Either plan must be
  imports only.
- **Step 4 or 5 fails partway:** what it imported and created is in state, and
  the old credentials are still valid, so consumers keep working whichever
  secrets were updated. Fix the cause and plan and apply again (step 5's way):
  the plan shows what's left.
- **A new credential doesn't work** (a check in step 6 fails): put the old
  value back from the backup, one secret at a time, without printing it. The
  old credential works until step 8, so this restores the consumer at once:

  ```sh
  age -d -i "$AGE_KEY" "$BACKUP_DIR/mini-min-$STAMP.json.age" \
    | jq -r .EXTERNALDNS_CLOUDFLARE_TOKEN \
    | doppler secrets set EXTERNALDNS_CLOUDFLARE_TOKEN -p k8s-at-home -c min >/dev/null
  ```

  (`doppler secrets set` reads a piped value from stdin and prints the secret
  table on success, hence `>/dev/null`.) Force-sync its ExternalSecret. The
  next plan of the owning stack then shows that secret updating back to the
  new credential: find why the new one failed before applying again.
- **`CLOUDFLARED_CREDENTIALS` or the restic password changed** (check 6.1
  says `NO`): restore the whole secret from the backup the same way, at once,
  and force-sync `network/cloudflared`, `network/cloudflared-substitution-secret`
  or the volsync ExternalSecrets. Then stop: the random resource in this
  state holds the wrong value and `ignore_changes` keeps an apply from
  correcting it. Fixing it means removing it from state and importing it by
  value again (a state edit, by hand).
- **After step 8** the old credentials are gone, so rollback is forward: a
  broken consumer gets a reissued credential (`-replace` its key or token
  here, and its Doppler secret follows).
- **Something destroyed:** nothing here plans a destroy, and the buckets, the
  tunnel and both random resources have `prevent_destroy`. Stop and look;
  never edit state by hand.

## CI

This stack is untagged, so CI plans it like any other: `terraform-plan` on
every PR that changes it, and the nightly `terraform-drift` (3:30 am) from the
moment it merges. Today both fail at **provider credentials**, and the drift
run then fails as a whole and alerts healthchecks.io every night:

| Needed in `tf-at-home/ci` | Today | Gap |
| --- | --- | --- |
| `CLOUDFLARE_MINI_TOKEN` | the CI read-only token (foundation's `mini_token.tf`) | it has no Cloudflare Tunnel Read, so the tunnel refresh 403s; add an account-level `Cloudflare Tunnel Read` policy to `ci_readonly` |
| `BACKBLAZE_APPLICATION_KEY_ID`, `BACKBLAZE_APPLICATION_KEY` | absent | a read-only B2 key: `listBuckets`, `readBuckets`, `listKeys` (refreshing `b2_application_key`), and whatever reading lifecycle and file-lock settings takes (`readBucketRetentions`?), no file reads. Made by hand (a stack can't safely hold the key it reads with), like `terraform-backblaze` |
| `DOPPLER_MINI_WRITE_TOKEN` | absent | refreshing `doppler_secret` needs a token that can **read `k8s-at-home/min`**, below |
| `TF_VAR_import_*` | never | until the cleanup PR, any plan without them fails by design: CI can plan this stack only after step 9 |

**Doppler is the hard one.** A read token on `k8s-at-home/min` reads every
secret of every app in mini (database passwords, OAuth secrets, ...), not just
the eight this stack writes, and it would sit in `tf-at-home/ci`, which every
PR plan job on the runner reads. Options:

1. **A Terraform-only config.** Move the secrets Terraform writes into their
   own Doppler config (e.g. a `k8s-at-home` environment `tf-min`), and make
   `min`'s keys Doppler references to it (`${tf-min.KEY}`), so ExternalSecrets
   read `min` unchanged. CI's token reads `tf-min` only, which holds exactly
   what this stack's state already holds. Costs one environment (check the
   free plan's limit) and a careful cutover of eight secrets. Recommended.
2. **Exclude the Doppler secrets from CI plans** (`ci-plan-exclude.txt`).
   CI never reads `min`, but its plans are partial and the apply workflow
   refuses stacks with excludes, so this stack could never be `ci-apply`.
3. **A read token on `min` in `ci`.** Simplest, and it exposes all of mini's
   app secrets to CI plan jobs. Not recommended.

Whatever the choice, CI's plan jobs can already decrypt this stack's state
once it exists (the shared passphrase, the read-only R2 token): it holds the
tunnel secret, the restic password, both Cloudflare tokens and three B2 keys.
That's the design for non-laptop-only stacks, but these are higher-value
than anything another CI-planned stack holds; making this stack
`laptop-only` instead would need its state re-encrypted.

**Applying from CI (`ci-apply`)** also puts `CLOUDFLARE_MINI_TOKEN`'s real
value in `ci-apply`. It has API Tokens Write, which can mint a token with any
permission the owner's user has, so any apply job could reach as far as
`CLOUDFLARE_TERRAFORM_TOKEN`. Options: keep this stack laptop-applied; or
move the external-dns and cert-manager tokens to foundation (laptop-only),
which leaves this stack's token Zone Read, DNS Write and Tunnel Write; or wait
for phase 3's account-owned tokens, which can be limited to an account but
still not to a set of permissions.

**Until then, keep CI off this stack.** Before merging the clusters/mini PR,
add a tag the three workflows skip, e.g. `ci-skip` alongside `laptop-only` in
each `tf_list` call of `terraform-plan.yaml`, `terraform-drift.yaml` and
`terraform-apply.yaml` (a workflow change, so the owner merges it). Unlike
`laptop-only` it keeps the shared passphrase, so dropping it later needs no
re-encryption.
