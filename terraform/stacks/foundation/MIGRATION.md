# Moving the foundation into home-ops (migration phase 2, P2-1)

A one-time runbook for the owner. It moves the R2 state bucket, its Doppler
secrets and CI's read-only credentials out of terraform-record's `cloudflare`
stack into this stack, and brings the hand-made Doppler projects,
environments, configs and write tokens under Terraform. Delete this file and
`imports.tf` in the cleanup PR (step 8).

**Laptop only.** This stack's default Doppler provider is your personal CLI
token (`DOPPLER_TOKEN`, set by `task tf:*`), because only a personal token can
create service tokens on the free plan. It never runs in CI.

## What moves, and how

| Object | Method |
| --- | --- |
| `cloudflare_r2_bucket.tofu_state` (`prevent_destroy`) | import |
| R2 tokens `tofu-state-readonly`/`-readwrite` | rotate: new `tofu-state-ci-plan-readonly` and `tofu-state-laptop-readwrite` here; the old ones stay in terraform-record until step 6 |
| `tf-at-home/prd` `R2_STATE_READONLY`, `R2_STATE_READWRITE` | import, pointed at the new R2 tokens |
| CI token `ci-plan-readonly-<date>` | rotate: new `home-ops-ci-plan-readonly-<date>` here, same 90-day rotation and expiry check; the old one stays until step 6 |
| `tf-at-home/ci` `CLOUDFLARE_TERRAFORM_TOKEN`, `R2_STATE_READONLY` | import, pointed at the new tokens |
| Doppler projects (4), environments (7), configs (10) | import (all hand-made); `prevent_destroy` on every one |
| Environment `tf-at-home/ci-apply` | create (empty; a later task fills it) |
| Root config `tf-at-home/ci-apply` | import: Doppler creates it with the environment, and the provider's create is refused on the free plan (#2202) |
| Write tokens: one `tf-stacks-write` service token per config Terraform writes to (`hosts-at-home/prd`, `k8s-at-home/min`, `tf-at-home/prd`, `tf-at-home/ci`, `tf-at-home/ci-apply`) | create |
| `tf-at-home/prd` `DOPPLER_TRUENAS_WRITE_TOKEN`, `DOPPLER_MINI_WRITE_TOKEN`, `DOPPLER_TF_WRITE_TOKEN`, `DOPPLER_TF_CI_WRITE_TOKEN` | import, pointed at the new write tokens. terraform-record's stacks read these names, so they pick the new tokens up unchanged |
| `tf-at-home/prd` `DOPPLER_TF_CI_APPLY_WRITE_TOKEN` | create |

Not moving: the nightly copy's token `tofu-state-copy` and `TOFU_STATE_R2_SOURCE`
(they stay in terraform-record, untouched), the break-glass R2 token, the
state passphrase, and the read-only service tokens (`doppler-eso`,
`doppler-export`, `ci-runner-plan`, `tfc-remote-runs`), which stay hand-made.

Since then (Nov 25, 2026): the `doppler-export` tokens were replaced by the
generated `export-read` ones (`doppler_export.tf`), and the three `tf-at-home`
write tokens were removed, since nothing used them.

## 0. Preconditions

- **Terraform Cloud version.** `removed` blocks need Terraform 1.7 or later,
  and remote runs use the version the workspace pins. Check
  `arpa-home-cloudflare` (prints the version and execution mode only):

  ```sh
  TFC=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
  curl -fsS -H "Authorization: Bearer $TFC" \
    https://app.terraform.io/api/v2/organizations/rtrox/workspaces/arpa-home-cloudflare \
    | jq -r '.data.attributes | "terraform-version=\(."terraform-version") execution-mode=\(."execution-mode")"'
  unset TFC
  ```

  Below 1.7: raise it in the workspace settings first. The PR also raises
  `required_version` to `>= 1.7.0`, so an older pin fails at init instead of
  misreading the `removed` blocks.
- **Baseline: both sides plan clean before anything moves.** On
  terraform-record `main`:
  `env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan` must say
  `No changes.` In home-ops: `task tf:plan STACK=proxmox` must say
  `No changes.` Anything else: stop and resolve it first, or it gets mixed up
  with the move.
- **Freeze.** From here to step 7, no applies to terraform-record `cloudflare`
  and no runs of this stack except the ones below. The other terraform-record
  stacks (`backblaze`, `minio`, `pocketid`) only read the write-token secrets;
  don't apply them during step 3, and they're unaffected otherwise, since the
  old tokens stay valid until step 6.
- **proxmox's state has no Doppler data source left, before any new
  `tf-at-home/prd` key is created.** Before #2201, proxmox read the whole of
  `tf-at-home/prd` through `data "doppler_secrets"`, which is stored in
  proxmox's state, and CI can decrypt that state with the shared passphrase.
  Any key added to `prd` while that data source is still in state lands there
  on proxmox's next refresh. So, once, since #2201 merged and **before** the
  two keys below:

  ```sh
  git switch main && git pull
  task tf:apply STACK=proxmox        # expect: No changes; answer yes if asked
  ```

  The apply writes proxmox's state again, without the data sources (they're
  no longer in its code). Check it: `task` has no `state` command, so this
  sets the backend environment the way `task tf:*` does, in a subshell, and
  prints only a count:

  ```sh
  (
    set -euo pipefail
    r2=$(doppler secrets get -p tf-at-home -c prd --plain R2_STATE_READWRITE)
    AWS_ACCESS_KEY_ID=$(jq -er .access_key_id <<<"$r2")
    AWS_SECRET_ACCESS_KEY=$(jq -er .secret_access_key <<<"$r2")
    AWS_ENDPOINT_URL_S3=$(jq -er .endpoint <<<"$r2")
    TF_VAR_state_passphrase=$(doppler secrets get -p tf-at-home -c prd --plain TOFU_STATE_PASSPHRASE)
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 TF_VAR_state_passphrase
    unset r2
    mise exec -- tofu -chdir=terraform/stacks/proxmox state list > /tmp/proxmox-state-list
    echo "resources=$(wc -l < /tmp/proxmox-state-list) doppler_data_sources=$(grep -c '^data\.doppler_secrets\.' /tmp/proxmox-state-list || true)"
    rm -f /tmp/proxmox-state-list
  )
  ```

  Expect `doppler_data_sources=0` and a nonzero `resources=`. Anything else:
  stop, and don't create the two keys below. (The
  addresses alone aren't secret, but the file is removed anyway.)
- **`TOFU_STATE_PASSPHRASE_LAPTOP` in `tf-at-home/prd`.** This stack is
  `laptop-only`, so `task tf:*` encrypts its state with this passphrase, never
  the shared `TOFU_STATE_PASSPHRASE`. CI holds the shared one and a read-only
  R2 token that reads every key in the bucket, so it could download this state
  but must never decrypt it (the state holds every write token and the R2
  read-write key). Generate it locally, never printed:

  ```sh
  openssl rand -base64 32 | tr -d '\n' \
    | doppler secrets set TOFU_STATE_PASSPHRASE_LAPTOP -p tf-at-home -c prd --silent >/dev/null
  ```

  Then **save a copy in Bitwarden** (copy it from the Doppler dashboard into
  a Bitwarden secure note, not through the terminal). **Break-glass:** this
  passphrase is the only key to foundation's state, and the state copy in B2 is
  encrypted with it too. Lose it (Doppler gone, no Bitwarden copy) and the state
  can't be read. The objects themselves survive, but you'd rebuild the stack by
  importing everything again and rotating every token it created. Never change
  it in place: a new passphrase needs a migration with the old one configured
  as a `fallback`. Without the key, `task tf:*` on this stack stops with an
  error; it never falls back to the shared passphrase.
- **`CLOUDFLARE_USER_ID` in `tf-at-home/prd`.** The CI token's user-scoped
  policy needs your Cloudflare user ID, which stays out of this public repo.
  `task tf:*` exports it as `TF_VAR_cloudflare_user_id` (the stack's
  `secret_vars`), a sensitive variable. It's laptop-only, so it stays out of
  `tf-at-home/ci` and `ci-apply`.
  Copy it from terraform-record's `cloudflare/ci_readonly.tf`, where it's still
  a literal, without printing it:

  ```sh
  grep -o 'com\.cloudflare\.api\.user\.[0-9a-f]\{32\}' ~/terraform-record/cloudflare/ci_readonly.tf \
    | head -1 | cut -d. -f5 | tr -d '\n' \
    | doppler secrets set CLOUDFLARE_USER_ID -p tf-at-home -c prd >/dev/null
  # Check the shape only: prints 1.
  doppler secrets get CLOUDFLARE_USER_ID -p tf-at-home -c prd --plain | grep -cE '^[0-9a-f]{32}$'
  ```

  (`doppler secrets set` reads a piped value from stdin and prints the secret
  table on success, hence `>/dev/null`.) Leave it `masked`, not `restricted`.
- **Back up the secrets that change**, age-encrypted, never printed. This is
  the rollback for step 3:

  ```sh
  BACKUP_DIR="$HOME/tofu-backups"; mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
  STAMP=$(date +%Y%m%dT%H%M%S)
  doppler secrets download -p tf-at-home -c prd --no-file --format json \
    | jq '{R2_STATE_READONLY, R2_STATE_READWRITE, DOPPLER_TRUENAS_WRITE_TOKEN,
           DOPPLER_MINI_WRITE_TOKEN, DOPPLER_TF_WRITE_TOKEN, DOPPLER_TF_CI_WRITE_TOKEN}' \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP_DIR/foundation-prd-$STAMP.json.age"
  doppler secrets download -p tf-at-home -c ci --no-file --format json \
    | jq '{CLOUDFLARE_TERRAFORM_TOKEN, R2_STATE_READONLY}' \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP_DIR/foundation-ci-$STAMP.json.age"
  # Check: key names only, and none null.
  for f in "$BACKUP_DIR"/foundation-*-"$STAMP".json.age; do
    age -d -i "$AGE_KEY" "$f" | jq -r 'to_entries[] | "\(.key) set=\(.value != null)"'
  done
  ```

  Expect six names in prd and two in ci, all `set=true`. Write down `$STAMP`
  (the rollback below uses these three variables).

## 1. Apply the terraform-record PR (forget, in TFC)

This is procedure step 2: the old stack lets go of everything that moves,
except the old credentials. Remote TFC runs must never receive your Doppler
CLI token, so unset it; the workspace's `doppler-read` variable set provides
the read-only one.

On the PR branch first, to check the plan, then merged:

```sh
cd ~/terraform-record
env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan -no-color 2>&1 \
  | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

Expect exactly these five, and nothing destroyed:

```text
  # cloudflare_r2_bucket.tofu_state will no longer be managed by Terraform
  # doppler_secret.ci_cloudflare_token will no longer be managed by Terraform
  # doppler_secret.ci_r2_state_readonly will no longer be managed by Terraform
  # doppler_secret.r2_state["readonly"] will no longer be managed by Terraform
  # doppler_secret.r2_state["readwrite"] will no longer be managed by Terraform
Plan: 0 to add, 0 to change, 0 to destroy, 5 to forget.
```

A `Warning: Some objects will no longer be managed by Terraform` is expected.
If the workspace's version words the summary differently, the five headers and
`0 to destroy` are what matter.

If `cloudflare_api_token.r2_state` or `r2_state_copy` shows an update to
`policies`, the bucket's jurisdiction isn't `default`: set
`local.r2_bucket_jurisdiction` in `cloudflare/r2_state.tf` to the value the
plan shows was there, and re-plan. `doppler_secret.r2_state_copy_mini` must
not appear at all.

Merge the PR, then from `main`:

```sh
git switch main && git pull
env -u TF_VAR_doppler_token tofu -chdir=cloudflare apply    # the same 5 to forget; yes
env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan     # No changes.
```

Nothing in Cloudflare or Doppler changes here; only TFC's state does. From now
until step 3, nothing manages those five objects, and nothing changes them.

## 2. Plan this stack

```sh
cd ~/home-ops
task tf:init STACK=foundation
task tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

The header lines show resource addresses and for_each keys only (project and
config names, never values). Expect:

```text
Plan: 31 to import, 11 to add, 8 to change, 0 to destroy.
```

- **31 imports**: `cloudflare_r2_bucket.tofu_state`; `doppler_project.this`
  ×4; `doppler_environment.this` ×7; `doppler_config.this` ×11 (including
  `tf-at-home/ci-apply`, which Doppler creates with its environment); and 8
  `doppler_secret`s (below). The bucket, projects, environments and configs
  are imported **with no change**: each shows `will be imported` and nothing
  else.
- **11 creates**: `cloudflare_api_token.r2_state["readonly"]` and
  `["readwrite"]`, `cloudflare_api_token.ci_readonly`,
  `time_rotating.ci_readonly_token`,
  `doppler_environment.this["tf-at-home/ci-apply"]`, `doppler_service_token.write`
  ×5 (one per config above), and
  `doppler_secret.write_token["tf-at-home/ci-apply"]`.
- **8 updates**, each also imported: `doppler_secret.r2_state["readonly"]`,
  `["readwrite"]`, `doppler_secret.ci_cloudflare_token`,
  `doppler_secret.ci_r2_state_readonly`, and `doppler_secret.write_token` for
  `hosts-at-home/prd`, `k8s-at-home/min`, `tf-at-home/prd` and
  `tf-at-home/ci`. Each changes `value` only (shown as `(sensitive value)`):
  that's the rotation onto the new tokens.

### If the plan shows anything else

Don't apply. A plan with imports changes nothing, so the fix is in code.

| You see | Meaning | Do |
| --- | --- | --- |
| `cloudflare_r2_bucket.tofu_state` **must be replaced** or updated | an attribute differs from the bucket (`prevent_destroy` blocks a replace anyway) | Match `r2_state.tf` to the plan's current value (`location`, `storage_class`, `jurisdiction`); re-plan |
| a project, environment or config **updated** (`description`, `name`, or an environment's `personal_configs`) | the Doppler setting differs from the code (all 7 environments had personal configs off on 2026-11-22; the provider defaults it to `false`) | Match `doppler.tf` to the live value (for `personal_configs`, add `personal_configs = true` to that environment); re-plan |
| a `doppler_secret` update showing `visibility` or `value_type` too | the hand-made secret isn't `masked`/`string` | Set `visibility`/`value_type` on that resource to the live value; re-plan. Only `value` may change |
| an error **reading** an imported `doppler_secret` | the secret is `restricted`: provider 1.23.2 can't read a restricted secret's value with a personal token, so the import fails | In the dashboard, set that secret's visibility to `masked` (the value is unchanged), then re-plan. Don't add `visibility = "restricted"` in code: the next refresh would fail the same way |
| `Cannot import non-existent remote object` | a project, config or secret name changed or is missing | Check it with `doppler configs` / `doppler secrets names`; fix `imports.tf` |
| precondition `CLOUDFLARE_USER_ID is missing` | step 0's secret isn't set, or isn't a 32-character hex ID | Redo that step; re-plan |
| 403 creating a Cloudflare token | the Terraform token lost API Tokens Write | The same token terraform-record uses: check it hasn't changed |
| `cloudflare_api_token.r2_state` **must be replaced** (`prevent_destroy` error) | a change that forces a new token | Not part of this move: fix the code. Rotating these is its own procedure (below) |
| **anything destroyed** | not intended | Stop |

A slug or environment-count problem with `tf-at-home/ci-apply` only shows at
apply time, not in the plan; step 3 applies that part first, on its own.

## 3. Merge, then apply

Merge the home-ops PR once step 2 matches, then apply from `main`, in two
parts.

**3a. The new `ci-apply` environment and config, alone.** Doppler may reject
the hyphenated slug `ci-apply` or a third `tf-at-home` environment (free plan),
and the plan can't tell. Only the apply finds out, so it goes first, before
any credential changes. Targeting all of `doppler_config.this` avoids quoting
an index through `task`; the other configs, their environments and projects
come along as no-change imports:

```sh
git switch main && git pull
task tf:apply STACK=foundation -- -target=doppler_config.this
```

Expect `Plan: 22 to import, 1 to add, 0 to change, 0 to destroy.` The one add
is `doppler_environment.this["tf-at-home/ci-apply"]`; its root config, which
Doppler creates with it, is one of the 22 imports. (On Nov 22 the first run
created the environment and then failed creating the config, before #2202; its
re-run is `1 to import, 0 to add`. Before re-running, check
`doppler_config.this["tf-at-home/ci-apply"]` isn't in the state.) The targeting warning is expected.
If the environment create fails, **stop and report**: nothing but imports has
happened (state only), and the `ci-apply` name is used by
`.github/workflows/terraform-apply.yaml`, so a different name is a design
change.

**3b. Everything else:**

```sh
task tf:plan STACK=foundation     # 9 to import, 10 to add, 8 to change, 0 to destroy
task tf:apply STACK=foundation    # review, then yes
```

The 9 imports are the bucket and the 8 `doppler_secret`s; the 10 adds are
step 2's creates minus the two from 3a.

The apply runs on the R2 credentials `task` read at its start (the old
read-write token), and those stay valid, so updating `R2_STATE_READWRITE`
mid-apply doesn't cut the stack off from its own state.

## 4. Check every consumer

1. **Laptop R2 (new read-write token):** `task tf:plan STACK=foundation` and
   `task tf:plan STACK=proxmox` both say `No changes.` Each run reads the new
   `R2_STATE_READWRITE` and writes and removes a lock file, so this proves
   read and write.
2. **CI plans (new read-only R2 token and new CI Cloudflare token in
   `tf-at-home/ci`):** re-run the latest `terraform-plan` run of a PR that
   planned `stacks/proxmox` only: `gh run list --workflow terraform-plan.yaml`,
   then `gh run rerun <id>`. The proxmox plan must succeed. (CI never plans
   `stacks/foundation`: it skips `laptop-only` stacks, and a PR touching one
   only says to plan it from the laptop.)
3. **Nightly `terraform-drift` (reads `tf-at-home/ci` too):** start it now
   with `gh workflow run terraform-drift.yaml`, and check that the run passes
   and its healthchecks.io check got a success ping. The next scheduled run
   (11:30 UTC) must pass too.
4. **terraform-record stacks (new write tokens, same secret names):** plan each
   and expect `No changes.` `backblaze` and `cloudflare` run remotely in TFC
   (no CLI token). `pocketid` (TFC local execution) and `minio` (S3 backend on
   B2, no TFC) run locally and need `var.doppler_token`; without it they'd
   prompt, invisibly behind the `grep`. `minio` also needs the B2 state key in
   `AWS_*` (terraform-record's README):

   ```sh
   cd ~/terraform-record
   for s in backblaze cloudflare; do env -u TF_VAR_doppler_token tofu -chdir=$s plan -input=false -no-color 2>&1 | grep -E '^Plan:|^No changes|^Error'; done
   for s in pocketid minio; do TF_VAR_doppler_token=$(doppler configure get token --plain) tofu -chdir=$s plan -input=false -no-color 2>&1 | grep -E '^Plan:|^No changes|^Error'; done
   ```

5. **`tofu-state-copy`:** unaffected. Its token (`tofu-state-copy`) and its
   secret (`TOFU_STATE_R2_SOURCE`) didn't change. Confirm the next nightly run
   pinged healthchecks.io.

## 5. Wait

Leave the old credentials for at least one nightly cycle (a scheduled
`terraform-drift` run, the `tofu-state-copy` run) and one CI PR plan, so a
consumer that reads at a different time also shows it's healthy. Until step
6, everything is reversible from the step 0 backup.

## 6. Revoke the old tokens

**Hand-made Doppler service tokens.** In each config, list them (names and
slugs only) and revoke the old write token by slug:

```sh
for pc in hosts-at-home/prd k8s-at-home/min tf-at-home/prd tf-at-home/ci; do
  doppler configs tokens -p "${pc%/*}" -c "${pc#*/}" --json | jq -r --arg pc "$pc" '.[] | "\($pc) \(.slug) \(.name) \(.access)"'
done
```

| Config | Revoke | Keep |
| --- | --- | --- |
| `hosts-at-home/prd` | `Terraform` (read/write) | `tf-stacks-write`, `doppler-export` |
| `k8s-at-home/min` | `Terraform` (read/write) | `tf-stacks-write`, `doppler-eso`, `doppler-export` |
| `tf-at-home/prd` | `terraform-cloudflare-tf-write` | `tf-stacks-write`, `tfc-remote-runs`, `doppler-export` |
| `tf-at-home/ci` | `terraform-cloudflare-ci-write` | `tf-stacks-write`, `ci-runner-plan` |

```sh
doppler configs tokens revoke <slug> -p <project> -c <config>
```

**"bitty tofu controller":** this token no longer exists anywhere. The owner
checked every config's service tokens and the CLI tokens on 2026-11-22; it was
presumably deleted with the bitty environment, so there is nothing to revoke.

Re-run step 4.4: all four terraform-record stacks still `No changes.` proves
nothing used the revoked tokens.

**Old Cloudflare tokens, via terraform-record** (procedure step 4): a
follow-up terraform-record PR (rtrox/terraform-record#63) deletes `cloudflare_api_token.r2_state`,
`cloudflare_api_token.ci_readonly`, `time_rotating.ci_readonly_token` and the
now-unused `doppler.tf_write` / `doppler.tf_ci_write` aliases. Its plan is the
retirement and nothing else:

```text
  # cloudflare_api_token.ci_readonly will be destroyed
  # cloudflare_api_token.r2_state["readonly"] will be destroyed
  # cloudflare_api_token.r2_state["readwrite"] will be destroyed
  # time_rotating.ci_readonly_token will be destroyed
Plan: 0 to add, 0 to change, 4 to destroy.
```

Apply it in TFC (`env -u TF_VAR_doppler_token`), then re-run steps 4.1 to
4.3.

## 7. Zero-diff gate

Both must say `No changes.`:

```sh
task tf:plan STACK=foundation
env -u TF_VAR_doppler_token tofu -chdir="$HOME/terraform-record/cloudflare" plan
```

The freeze ends here.

## 8. Cleanup

A home-ops PR deletes `imports.tf` and this file (its plan: `No changes.`).
Delete the step 0 backups once the gate has held for a week.

## If an apply goes wrong

- **Step 1 (forget) misbehaves:** forgetting edits only TFC's state; nothing
  in Cloudflare or Doppler changed. Don't apply this stack. Revert the
  terraform-record PR and adopt the five objects back with `import` blocks in
  `cloudflare/` (bucket `<account_id>/tofu-state/default`; secrets
  `tf-at-home.prd.R2_STATE_READONLY`, `...R2_STATE_READWRITE`,
  `tf-at-home.ci.CLOUDFLARE_TERRAFORM_TOKEN`, `tf-at-home.ci.R2_STATE_READONLY`);
  that plan must be imports only.
- **Step 3 fails partway:** what it imported and created is in this stack's
  state, and the old credentials are still valid, so consumers keep working
  whichever secrets were updated. Fix the cause and apply again; the plan
  shows what's left.
- **A new credential doesn't work** (for example `task tf:*` gets 403 from R2,
  CI plans fail, or a terraform-record stack can't configure its Doppler
  provider): put the old value back from the step 0 backup, one secret at a
  time, without printing it:

  ```sh
  age -d -i "$AGE_KEY" "$BACKUP_DIR/foundation-prd-$STAMP.json.age" \
    | jq -r .R2_STATE_READWRITE \
    | doppler secrets set R2_STATE_READWRITE -p tf-at-home -c prd >/dev/null
  ```

  (`doppler secrets set` reads a piped value from stdin, and prints the
  secret table on success, hence `>/dev/null`. Check `doppler secrets set
  --help` on your CLI version first.)

  **`R2_STATE_READONLY` lives in two configs**, `prd` and its copy in `ci`
  (which CI and `terraform-drift` read). Restore both, or they disagree:

  ```sh
  for c in prd ci; do
    age -d -i "$AGE_KEY" "$BACKUP_DIR/foundation-$c-$STAMP.json.age" \
      | jq -r .R2_STATE_READONLY \
      | doppler secrets set R2_STATE_READONLY -p tf-at-home -c "$c" >/dev/null
  done
  ```

  The CI Cloudflare token is `ci`'s `CLOUDFLARE_TERRAFORM_TOKEN` (from
  `foundation-ci-*`). Never restore `prd`'s `CLOUDFLARE_TERRAFORM_TOKEN`: it
  isn't in the backup, and this stack doesn't manage it.

  The old tokens work until step 6, so this restores the consumer at once.
  The next plan of this stack then shows that secret updating back to the new
  token: find why the new one failed before applying it again. If even the
  laptop's R2 access is gone, the break-glass R2 token (outside Doppler) gets
  you back into the state.
- **Something destroyed:** nothing here plans a destroy, and the bucket,
  projects, environments, configs and R2 tokens all have `prevent_destroy`.
  Stop and look; never edit state by hand.

## Rotating the R2 tokens later

Not part of this move; kept here until a permanent runbook exists.
`cloudflare_api_token.r2_state` has `prevent_destroy`: every stack's backend,
this one's included, logs in with these tokens, and a replacement in an
ordinary apply would delete the read-write token while that apply still needs
it to write state and release the lock (a 403, a stale lock, and possibly
unsaved state). So rotate deliberately, logged in as the break-glass key:

1. Freeze every stack (no plans or applies, CI included: pause the
   `terraform-apply` and `terraform-drift` workflows with `gh workflow
   disable`).
2. In a fresh shell, put the break-glass R2 key in `AWS_ACCESS_KEY_ID` /
   `AWS_SECRET_ACCESS_KEY` / `AWS_ENDPOINT_URL_S3`, from wherever it's kept
   outside Doppler, `TF_VAR_state_passphrase` from
   `TOFU_STATE_PASSPHRASE_LAPTOP` (this stack's own, not the shared one),
   `DOPPLER_TOKEN` as `task tf:*` sets it, and every variable in this stack's
   `_provider_env.json` (`CLOUDFLARE_API_TOKEN`, `TF_VAR_cloudflare_user_id`)
   from `tf-at-home/prd`. Run `mise exec -- tofu` in this directory directly:
   `task` would overwrite `AWS_*` from Doppler.
3. Temporarily remove `prevent_destroy` from `cloudflare_api_token.r2_state`
   (a local, uncommitted edit). A name change alone updates a token in place
   and keeps its secret, so force the replacement instead.
4. `tofu plan '-replace=cloudflare_api_token.r2_state["readwrite"]'` (and/or
   `["readonly"]`): expect that token replaced (create before destroy) and its
   `R2_STATE_*` updated (for `readonly`, `ci`'s copy too), nothing else. Apply
   with the same `-replace`. The state write and lock release use the
   break-glass key, so the old token going away mid-apply doesn't matter.
5. Restore `prevent_destroy` (`git diff` is empty again), then check every
   consumer as in step 4 above. Re-enable the workflows.

# P2-1b: CI's apply credentials and the GitHub Environments

Run this **after** the P2-1 move above has been applied (step 7's zero-diff
gate passed): the plan counts below assume `No changes.` beforehand. The PR
adds `ci_apply.tf` and `environments.tf`, the `github` provider (generated, so
`_provider_env.json` now also exports `GITHUB_TOKEN`) and the import of the two
Environments. Still laptop-only; it never runs in CI.

What it makes:

| Object | Method |
| --- | --- |
| R2 token `tofu-state-ci-apply-readwrite-<date>` (read/write on the `tofu-state` bucket), reissued every 90 days like the CI read-only token, with an expiry check | create, with `time_rotating.r2_state_ci_apply`; its own token, so it is revoked alone |
| `tf-at-home/ci-apply` `R2_STATE_READWRITE` (same JSON shape as in `prd`) | create |
| Service token `ci-apply-read` (read-only, `tf-at-home/ci-apply`) | create |
| Environments `tofu-apply-gated` (reviewer `rtrox`, `main` only) and `tofu-apply` (no reviewers, `main` only) of `rtrox/home-ops` | import, no change |
| Their branch policies (`main`) | import, no change |
| Environment secret `CI_DOPPLER_TF_APPLY` on **both** Environments, holding `ci-apply-read`'s key | create |
| `tf-at-home/ci-apply` `TOFU_STATE_PASSPHRASE` | **by hand**: a Doppler reference (step 1) |

Not here, on purpose: provider tokens per stack (added to `ci-apply` when a
stack opts in to `ci-apply`); `hosts-at-home/ci-apply` and
`DOPPLER_HOSTS_TOKEN` (the apply workflow and `tf-ci.sh` still read it, but
optionally, and no stack needs it yet, so nothing creates it); and the rest of
GitHub (phase 7).

## 0. Preconditions

- **The GitHub token.** Create a fine-grained personal access token on the
  account that owns `home-ops`: repository access **only `home-ops`**;
  permissions **Environments: read and write** (it covers the Environment
  secrets too) and **Actions: read** (reading Environments and their branch
  policies needs it; it only works without while the repo is public), plus the
  Metadata read GitHub adds itself. Nothing else. If you already made the token
  with Secrets and Administration, edit it down to this. Give it an expiry (90
  days or so) and **note the date in Bitwarden**. Put it in Doppler without
  printing it:

  ```sh
  doppler secrets set GITHUB_TERRAFORM_TOKEN -p tf-at-home -c prd   # paste at the prompt
  ```

  Until it exists, `task tf:*` for `foundation` fails reading the provider
  environment. **An expired token blocks every foundation plan and apply**,
  including the emergency R2 token rotation and the CI read-only token
  reissue, so renew it before it expires.
- P2-1 applied, and `task tf:plan STACK=foundation` says `No changes.`

## 1. The passphrase reference, by hand

Terraform must never hold the shared passphrase, and a `doppler_secret` would:
the provider stores the resolved value in state (its `computed` attribute). So
this one secret is made with the CLI, not in code. `ci-apply` gets a reference
to `prd`'s value, not a copy:

```sh
doppler secrets set TOFU_STATE_PASSPHRASE '${prd.TOFU_STATE_PASSPHRASE}' -p tf-at-home -c ci-apply >/dev/null
```

Single quotes, so the shell doesn't expand it. `${prd.X}` is Doppler's syntax
for another config of the same project (`${project.config.X}` for another
project). Doppler's docs weren't reachable when this was written, so step 4.3
checks that it resolves for a service token. Rotating `prd`'s passphrase later
changes what CI reads with no second edit.

## 2. Plan

```sh
git switch main && git pull
task tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

Expect exactly:

```text
Plan: 4 to import, 6 to add, 0 to change, 0 to destroy.
```

- **4 imports**: `github_repository_environment.this["tofu-apply-gated"]` and
  `["tofu-apply"]`; `github_repository_environment_deployment_policy.main["tofu-apply-gated"]`
  and `["tofu-apply"]`. Each shows `will be imported` and nothing else.
- **6 creates**: `time_rotating.r2_state_ci_apply`, `cloudflare_api_token.r2_state_ci_apply`,
  `doppler_secret.ci_apply_r2_state`, `doppler_service_token.ci_apply_read`,
  and `github_actions_environment_secret.ci_doppler_tf_apply["tofu-apply-gated"]`
  and `["tofu-apply"]`.
- **0 changes.** (`prevent_self_review` is ignored: the provider doesn't read
  it back for an Environment without reviewers, upstream #3583.) If an Environment or policy shows an update, don't apply: the
  code differs from the live Environment. Read it again
  (`gh api repos/rtrox/home-ops/environments/<env>` and its
  `/deployment-branch-policies`) and match `environments.tf`. Likely
  suspects: `wait_timer`, `can_admins_bypass`, `prevent_self_review`,
  `reviewers`.
- A 404 or `Cannot import non-existent remote object` on an Environment or
  policy: the token can't see `home-ops`, or a name or policy ID changed
  (`imports.tf` holds the policy IDs).
- 403 reading Environments or secrets: the token lacks a permission from
  step 0.
- **Anything destroyed**: stop.

## 3. Apply

```sh
task tf:apply STACK=foundation    # review, then yes
```

The Environment secrets are written last, once the service token exists.

## 4. Check

1. **Names only**, never values; each prints `CI_DOPPLER_TF_APPLY`:

   ```sh
   for e in tofu-apply-gated tofu-apply; do
     gh api repos/rtrox/home-ops/environments/$e/secrets --jq '.secrets[].name'
   done
   ```

2. `task tf:plan STACK=foundation` says `No changes.`
3. **`ci-apply` reads, and the reference resolves for a service token.** A
   dispatch of `terraform-apply` with no `ci-apply` stacks passes, but it does
   **not** read `ci-apply`: the plan job uses the read-only token, and the
   apply job is skipped when nothing changes. So check from the laptop, with a
   throwaway read token, printing only key names and yes/no answers:

   ```sh
   (
     set -euo pipefail
     tok=$(doppler configs tokens create tmp-check -p tf-at-home -c ci-apply --max-age 10m --plain)
     secrets=$(curl -fsS -K - "https://api.doppler.com/v3/configs/config/secrets/download?format=json" \
       <<<"header = \"Authorization: Bearer $tok\"")
     jq -r 'keys[]' <<<"$secrets"
     jq -e '.R2_STATE_READWRITE | fromjson | has("access_key_id") and has("secret_access_key") and has("endpoint")' <<<"$secrets" >/dev/null && echo "R2_STATE_READWRITE shape ok"
     a=$(jq -j .TOFU_STATE_PASSPHRASE <<<"$secrets" | sha256sum)
     b=$(doppler secrets get TOFU_STATE_PASSPHRASE -p tf-at-home -c prd --plain | tr -d '\n' | sha256sum)
     [ "$a" = "$b" ] && echo "passphrase matches prd: yes" || echo "passphrase matches prd: NO"
   )
   doppler configs tokens -p tf-at-home -c ci-apply --json | jq -r '.[] | "\(.slug) \(.name) \(.access)"'
   doppler configs tokens revoke <slug of tmp-check> -p tf-at-home -c ci-apply
   ```

   Expect the key names `R2_STATE_READWRITE` and `TOFU_STATE_PASSPHRASE`,
   the shape line, and `passphrase matches prd: yes`. A `NO`, or the literal
   `${prd.` text where the value should be, means the reference doesn't resolve
   for service tokens or its syntax is wrong: stop and tell the lead before
   anything depends on it. The token list shows `ci-apply-read` (read),
   `tf-stacks-write` (read/write) and `tmp-check`; revoke `tmp-check` by its
   slug.
4. **When the first stack opts in** to `ci-apply`, its apply run reads
   `ci-apply` through `CI_DOPPLER_TF_APPLY` for real; the `Read credentials`
   step passing is the end-to-end check, passphrase reference included. A
   failure prints only `could not read the CI credentials from Doppler`.

## If this goes wrong

- A failed apply leaves what it made in state: fix the cause and apply again.
  Nothing here changes an existing credential, so no existing consumer is
  affected.
- To back out: remove `ci_apply.tf`'s resources in a PR; its plan shows the
  destroys of the token, secret and service token. Never remove the
  Environments from the code without a `removed` block (`destroy = false`):
  they're imported, and the plain removal would delete them.
