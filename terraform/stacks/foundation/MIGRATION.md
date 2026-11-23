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
| Environment and root config `tf-at-home/ci-apply` | create (empty; a later task fills it) |
| Write tokens: one `tf-stacks-write` service token per config Terraform writes to (`hosts-at-home/prd`, `k8s-at-home/min`, `tf-at-home/prd`, `tf-at-home/ci`, `tf-at-home/ci-apply`) | create |
| `tf-at-home/prd` `DOPPLER_TRUENAS_WRITE_TOKEN`, `DOPPLER_MINI_WRITE_TOKEN`, `DOPPLER_TF_WRITE_TOKEN`, `DOPPLER_TF_CI_WRITE_TOKEN` | import, pointed at the new write tokens. terraform-record's stacks read these names, so they pick the new tokens up unchanged |
| `tf-at-home/prd` `DOPPLER_TF_CI_APPLY_WRITE_TOKEN` | create |

Not moving: the nightly copy's token `tofu-state-copy` and `TOFU_STATE_R2_SOURCE`
(they stay in terraform-record, untouched), the break-glass R2 token, the
state passphrase, and the read-only service tokens (`doppler-eso`,
`doppler-export`, `ci-runner-plan`, `tfc-remote-runs`), which stay hand-made.

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
Plan: 30 to import, 12 to add, 8 to change, 0 to destroy.
```

- **30 imports**: `cloudflare_r2_bucket.tofu_state`; `doppler_project.this`
  ×4; `doppler_environment.this` ×7; `doppler_config.this` ×10; and 8
  `doppler_secret`s (below). The bucket, projects, environments and configs
  are imported **with no change**: each shows `will be imported` and nothing
  else.
- **12 creates**: `cloudflare_api_token.r2_state["readonly"]` and
  `["readwrite"]`, `cloudflare_api_token.ci_readonly`,
  `time_rotating.ci_readonly_token`,
  `doppler_environment.this["tf-at-home/ci-apply"]`,
  `doppler_config.this["tf-at-home/ci-apply"]`, `doppler_service_token.write`
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
| a project, environment or config **updated** (`description`, `name`) | the Doppler value changed since 2026-11-22 | Match `doppler.tf` to the live value; re-plan |
| a `doppler_secret` update showing `visibility` or `value_type` too | the hand-made secret isn't `masked`/`string` | Set `visibility`/`value_type` on that resource to the live value; re-plan. Only `value` may change |
| `Cannot import non-existent remote object` | a project, config or secret name changed or is missing | Check it with `doppler configs` / `doppler secrets names`; fix `imports.tf` |
| 403 on `data.cloudflare_user.owner` | `CLOUDFLARE_TERRAFORM_TOKEN` can't read the user | Add **User Details Read** to that token's user policy in the dashboard, then re-plan |
| 403 creating a Cloudflare token | the Terraform token lost API Tokens Write | The same token terraform-record uses: check it hasn't changed |
| error creating `doppler_environment.this["tf-at-home/ci-apply"]` | Doppler refused the slug or the environment count | Stop and report; it changes the `ci-apply` design |
| **anything destroyed** | not intended | Stop |

## 3. Merge, then apply

Merge the home-ops PR once step 2 matches, then apply from `main`:

```sh
git switch main && git pull
task tf:plan STACK=foundation     # the same 30 / 12 / 8 / 0
task tf:apply STACK=foundation    # review, then yes
```

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
   then `gh run rerun <id>`. The proxmox plan must succeed. (A run that
   includes `stacks/foundation` fails until CI skips `laptop-only` stacks;
   that's expected.)
3. **terraform-record stacks (new write tokens, same secret names):** plan each
   and expect `No changes.`:

   ```sh
   cd ~/terraform-record
   for s in backblaze cloudflare minio; do env -u TF_VAR_doppler_token tofu -chdir=$s plan -no-color 2>&1 | grep -E '^Plan:|^No changes|^Error'; done
   TF_VAR_doppler_token=$(doppler configure get token --plain) tofu -chdir=pocketid plan -no-color 2>&1 | grep -E '^Plan:|^No changes|^Error'
   ```

   (`minio` also needs the B2 state key in `AWS_*`; see terraform-record's
   README.)
4. **`tofu-state-copy`:** unaffected. Its token (`tofu-state-copy`) and its
   secret (`TOFU_STATE_R2_SOURCE`) didn't change. Confirm the next nightly run
   pinged healthchecks.io.

## 5. Wait

Leave the old credentials for at least one nightly cycle and one CI run, so a
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

**"bitty tofu controller":** no config's service tokens had that name on
2026-11-22 (it may have gone with the deleted `bty` config). If it still
exists, it's a personal token: check the dashboard's account **Tokens** page
and revoke it there, after confirming the TFC variable set `doppler-read`
holds `tfc-remote-runs`, not it.

Re-run step 4.3: all four terraform-record stacks still `No changes.` proves
nothing used the revoked tokens.

**Old Cloudflare tokens, via terraform-record** (procedure step 4): a
follow-up terraform-record PR deletes `cloudflare_api_token.r2_state`,
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

Apply it in TFC (`env -u TF_VAR_doppler_token`), then re-run step 4.1 and 4.2.

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

  The old tokens work until step 6, so this restores the consumer at once.
  The next plan of this stack then shows that secret updating back to the new
  token: find why the new one failed before applying it again. If even the
  laptop's R2 access is gone, the break-glass R2 token (outside Doppler) gets
  you back into the state.
- **Something destroyed:** nothing here plans a destroy, and the bucket,
  projects, environments and configs all have `prevent_destroy`. Stop and
  look; never edit state by hand.
