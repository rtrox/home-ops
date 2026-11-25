# Moving TrueNAS's Terraform into home-ops (migration phase 2, P2-5)

A one-time runbook for the owner. It moves the two TrueNAS hosts' records and
the main TrueNAS's backup bucket out of terraform-record's `cloudflare` and
`backblaze` stacks into this stack, and their ACME DNS-01 tokens into
`foundation`. The cleanup PR (step 10) deletes this file, `imports.tf`,
`p2-5-plan.json`, and foundation's `imports.tf` and `p2-5-plan*.json`.

The PRs, in merge order:

| PR | What | Merged at |
| --- | --- | --- |
| home-ops #2256 | foundation: `CLOUDFLARE_TRUENAS_TOKEN`, the two ACME tokens, their imports | step 1 |
| rtrox/terraform-record#72 | forget what moves, except the old tokens and key | step 3 |
| home-ops #2257 | this stack | step 5 |
| rtrox/terraform-record#73 | delete the old tokens and key (rebase onto `main` after #72 merges) | step 9 |

The stack is tagged `laptop-only`, like foundation: CI never plans, applies
or drift-checks it, and `task tf:*` encrypts its state with
`TOFU_STATE_PASSPHRASE_LAPTOP` (never the shared passphrase), so CI can't
decrypt the B2 key it holds. Merging either home-ops PR still runs
`terraform-apply` for the `ci-apply` stacks (it plans all of them on any
`terraform/**` change), which should say `No changes.` for each.

## What moves, and how

| Object | To | Method |
| --- | --- | --- |
| `nas.rtrox.io` A 172.21.1.12 (`rtrox_io_host["nas"]`) | `cloudflare_dns_record.host["nas.rtrox.io"]`, address from `inventory/hosts.yaml` | import by ID |
| `backup.rtrox.io` A 172.30.1.13 (`rtrox_io_host["backup"]`) | `cloudflare_dns_record.host["backup.rtrox.io"]`, same | import by ID |
| Bucket `nas-rtrox-io-truenas-backup` (private, no lifecycle rules, no Object Lock) | `module.nas_backup_bucket` | import, unchanged |
| Its key `nas-rtrox-io-truenas-backup` | new key, same name and capabilities | rotate |
| `TRUENAS_BACKUP_BUCKET` (same JSON keys) | `doppler_secret.nas_backup_bucket` | import, updated to the new key |
| Tokens `truenas-cloudflare-api-token`, `truenas-backup-cloudflare-api-token` | foundation: new `nas-rtrox-io-acme-dns01`, `backup-rtrox-io-acme-dns01` (Zone Read, DNS Write on rtrox.io) | rotate |
| `TRUENAS_CLOUDFLARE_TOKEN`, `TRUENAS_BACKUP_CLOUDFLARE_TOKEN` | foundation: `doppler_secret.truenas_acme_token[<host>]` | import, updated to the new tokens |

Foundation writes the two token secrets to `hosts-at-home/prd` with the
owner's own Doppler token, not `DOPPLER_TRUENAS_WRITE_TOKEN`: deliberate, as
for every Doppler write in foundation (P2-3 did the same for
`k8s-at-home/min`), so foundation never depends on the write tokens it mints.
This stack writes `TRUENAS_BACKUP_BUCKET` with `DOPPLER_TRUENAS_WRITE_TOKEN`.

Not moving: `pve.rtrox.io` (stays in terraform-record until the proxmox stack
takes it) and the duplicacy bucket (MinIO, until phase 4). Nothing is
imported by value. The inventory, terraform-record and the live records
(public DNS, 2026-11-24) all agree on both addresses, so the imports change
nothing.

Every value here reaches TrueNAS only by the owner pasting it in (step 6).
Until then TrueNAS keeps using the old ones, which stay valid until step 9.
The one exception is the backup TrueNAS: its authenticator already holds a
deleted token (rtrox/terraform-record#53), so its renewals are broken now and
step 6b fixes them.

## Conventions

- **Every plan is separate from its apply, with a stop in between.** Plan to
  a file, check it, read it, and only then apply that same file.
- **Machine check.** `task tf:check-plan STACK=<stack> PLAN=<file>
  EXPECT=<json>` prints addresses and kinds only, and fails on anything not
  in the expectation file: an unexpected change or import, a missing one, any
  destroy, an update to anything but `value`, or a new Doppler value that
  isn't built from what the apply creates.
- **Secrets never on screen.** Values only move through pipes and the
  clipboard. Checks compare SHA-256 hashes and print `yes`/`NO`, or a short
  hash prefix where the two sides are on different machines. No
  here-strings: zsh writes those to temp files. `TF_LOG` is unset for every
  run:

  ```sh
  tf() { env -u TF_LOG -u TF_LOG_PATH task "$@"; }
  h() { sha256sum | cut -c1-64; }
  dop() { doppler secrets get "$1" -p hosts-at-home -c prd --plain | jq -Rsj 'rtrimstr("\n")'; }
  dopf() { doppler secrets get "$1" -p hosts-at-home -c prd --plain | jq -j --arg f "$2" '.[$f]'; }
  bak() { age -d -i "$AGE_KEY" "$BACKUP_DIR/truenas-$STAMP.json.age" | jq -j --arg k "$1" --arg f "${2:-}" 'if $f == "" then .[$k] else (.[$k] | fromjson | .[$f]) end'; }
  same() { if [ "$2" = "$3" ]; then echo "$1: yes"; else echo "$1: NO"; fi; }
  differ() { if [ "$2" != "$3" ]; then echo "$1: yes"; else echo "$1: NO"; fi; }
  # The clipboard, for pasting into the TrueNAS UI. Clear it after each paste.
  clip() { if command -v pbcopy >/dev/null; then pbcopy; elif command -v wl-copy >/dev/null; then wl-copy; else xclip -selection clipboard; fi; }
  clipclear() { printf ' ' | clip; }
  # A token's status at Cloudflare (prints active/disabled/expired only).
  cfverify() { jq -Rsj 'rtrimstr("\n") | "header = \"Authorization: Bearer \(.)\"\n"' | curl -fsS -K - https://api.cloudflare.com/client/v4/user/tokens/verify | jq -r '.result.status'; }
  ```

  Every `NO` below means stop, unless the step says otherwise.

## 0. Preconditions

- **TFC workspaces.** Both must run Terraform 1.7 or later, in **remote**
  execution mode, and must **not** auto-apply from VCS:

  ```sh
  TFC=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
  for w in arpa-home-cloudflare arpa-home-backblaze; do
    printf 'header = "Authorization: Bearer %s"\n' "$TFC" \
      | curl -fsS -K - "https://app.terraform.io/api/v2/organizations/rtrox/workspaces/$w" \
      | jq -r --arg w "$w" '.data.attributes | "\($w) version=\(."terraform-version") mode=\(."execution-mode") auto-apply=\(."auto-apply") vcs=\(."vcs-repo" != null)"'
  done
  unset TFC
  ```

  Note which say `vcs=true`: TFC refuses CLI applies there, so steps 3b and
  9b confirm their VCS runs in the UI instead.
- **The laptop passphrase is there.** `task tf:*` stops if
  `TOFU_STATE_PASSPHRASE_LAPTOP` is missing from `tf-at-home/prd`, and never
  falls back. Foundation already uses it; check without printing it:
  `doppler secrets get TOFU_STATE_PASSPHRASE_LAPTOP -p tf-at-home -c prd --plain | wc -c`
  prints a number above 16. Its Bitwarden copy now covers this stack's state
  too.
- **Baseline: everything plans clean.** On terraform-record `main`,
  `env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan` and the same for
  `backblaze`; here, `tf tf:plan STACK=foundation`. Each says `No changes.`
- **Freeze**, from here to step 9:
  - no applies to terraform-record `cloudflare` or `backblaze`, `foundation`
    or this stack except the ones below;
  - no edits in either TrueNAS UI to the ACME authenticators, the B2 cloud
    credential or the Cloud Sync task, except step 6;
  - no `inventory/hosts.yaml` edits to `nas.rtrox.io` or `backup.rtrox.io`;
  - no Renovate merges that touch `terraform/**` or terraform-record.
- **Note each TrueNAS's names**, in its UI: the Cloudflare ACME
  DNS-authenticator (Credentials > Certificates > ACME DNS-Authenticators),
  the ACME certificate it renews and that certificate's expiry; on the main
  TrueNAS also the B2 cloud credential (Credentials > Backup Credentials >
  Cloud Credentials) and the Cloud Sync task that uses it (Data Protection >
  Cloud Sync Tasks), with its last run's status.
- **Back up the secrets that change**, age-encrypted, never printed. This is
  the rollback until step 9:

  ```sh
  BACKUP_DIR="$HOME/tofu-backups"; mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
  STAMP=$(date +%Y%m%dT%H%M%S)
  doppler secrets download -p hosts-at-home -c prd --no-file --format json \
    | jq '{TRUENAS_CLOUDFLARE_TOKEN, TRUENAS_BACKUP_CLOUDFLARE_TOKEN, TRUENAS_BACKUP_BUCKET}' \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP_DIR/truenas-$STAMP.json.age"
  age -d -i "$AGE_KEY" "$BACKUP_DIR/truenas-$STAMP.json.age" | jq -r 'to_entries[] | "\(.key) set=\(.value != null)"'
  ```

  Expect three names, all `set=true`. Keep `BACKUP_DIR`, `AGE_KEY` and
  `STAMP` for the whole run.
- **The old tokens in Doppler are live.** Both are terraform-record's
  current tokens; only the backup TrueNAS's UI holds an older, deleted one.
  Expect `active` twice:

  ```sh
  bak TRUENAS_CLOUDFLARE_TOKEN | cfverify
  bak TRUENAS_BACKUP_CLOUDFLARE_TOKEN | cfverify
  ```

  If the backup's isn't `active`, the backup TrueNAS's stopgap in
  [If something goes wrong](#if-something-goes-wrong) doesn't exist: note it
  and carry on.

## 1. Foundation: the truenas stack's token alone

Merge #2256. Then plan only the token, check it, stop, and apply:

```sh
cd ~/home-ops && git switch main && git pull
P="$BACKUP_DIR/foundation-token-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" -target=doppler_secret.truenas_token_prd 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-5-plan-token.json
```

Expect `Plan: 3 to add, 0 to change, 0 to destroy.`
(`time_rotating.truenas_token`, `cloudflare_api_token.truenas`,
`doppler_secret.truenas_token_prd`), a targeting warning, and `PASS: 3
changes`. **Stop and read it.** Then:

```sh
tf tf:apply STACK=foundation -- "$P" && rm -f "$P"
```

**Never apply foundation untargeted before step 4.** Its imports would adopt
secrets terraform-record still manages.

## 2. Plan both new stacks, before anything is forgotten

```sh
P="$BACKUP_DIR/foundation-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-5-plan.json; rm -f "$P"
```

Expect `Plan: 2 to import, 2 to add, 2 to change, 0 to destroy.` and `PASS: 4
changes`: `cloudflare_api_token.truenas_acme["nas.rtrox.io"]` and
`["backup.rtrox.io"]` created; `doppler_secret.truenas_acme_token[...]` for
both imported and updated, `value` only.

This stack, from #2257's branch:

```sh
git switch p2-5/truenas && git pull
tf tf:init STACK=truenas
P="$BACKUP_DIR/truenas-$STAMP.tfplan"
tf tf:plan STACK=truenas -- -no-color -out="$P" 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=truenas PLAN="$P" EXPECT=p2-5-plan.json; rm -f "$P"
```

Expect `Plan: 4 to import, 1 to add, 1 to change, 0 to destroy.` and `PASS: 5
changes`:

- **4 imports**: `cloudflare_dns_record.host["nas.rtrox.io"]` and
  `["backup.rtrox.io"]` and `module.nas_backup_bucket.b2_bucket.this`, each
  `will be imported` and nothing else; and `doppler_secret.nas_backup_bucket`,
  also updated (below).
- **1 create**: `module.nas_backup_bucket.b2_application_key.this["nas-rtrox-io-truenas-backup"]`.
- **1 update**, `value` only: `doppler_secret.nas_backup_bucket`.

### If a plan or check shows anything else

Don't apply. Fix the code and plan again.

| You see | Meaning | Do |
| --- | --- | --- |
| the bucket updated (lifecycle rules, file lock, type, CORS, encryption) | the code differs from the bucket | Match `backup_bucket.tf` to the plan's current values (B2 returns lifecycle rules sorted by `file_name_prefix`: list them that way). A bucket's settings don't change in this move |
| the bucket **must be replaced** (`prevent_destroy` error) | name or file lock differs | Same: match the code. Never let it replace |
| a record updated | content, comment, proxied or TTL differ | Match `main.tf` (comment) or `inventory/hosts.yaml` (address) to the live record |
| a `doppler_secret` update showing `visibility` or `value_type` | the secret isn't `masked`/`string` | Set that attribute to the live value; only `value` may change |
| a 403 on the zone or a record | `CLOUDFLARE_TRUENAS_TOKEN` lacks a permission | Fix foundation's `truenas_token.tf` and redo step 1 |
| `FAIL:` from the check | the plan differs from the expectation file | Read the line; never edit the JSON to make a surprise pass |
| **anything destroyed** | not intended | Stop |

## 3. Forget, in terraform-record (TFC)

**3a. Plan #72** on its branch, in each workspace. Remote TFC runs
must never get your Doppler CLI token, so unset it:

```sh
cd ~/terraform-record && git fetch && git switch p2/truenas-forget && git pull
for s in cloudflare backblaze; do
  env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=$s plan -no-color 2>&1 \
    | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
done
```

`cloudflare`: 2 records moved to
`cloudflare_dns_record.rtrox_io_host_moved_to_truenas["nas"]` and
`["backup"]`, then 4 forgotten: those 2 records,
`doppler_secret.cf_api_token_truenas` and `.cf_api_token_truenas_backup`.
`Plan: 0 to add, 0 to change, 0 to destroy, 4 to forget.` The old tokens
(`module.cf_api_token_truenas*`) and `rtrox_io_host["pve"]` must **not**
appear.

`backblaze`: the key moved from
`module.bb_bucket_truenas_backup.b2_application_key.keys["nas-rtrox-io-truenas-backup"]`
to `b2_application_key.old_truenas_backup` with no change, then 2 forgotten:
`module.bb_bucket_truenas_backup.b2_bucket.bucket` and
`doppler_secret.truenas_backup_key`.
`Plan: 0 to add, 0 to change, 0 to destroy, 2 to forget.` If the moved key
shows any update or replacement, an argument differs from the module's: a
replaced key would cut Cloud Sync off.

The `Warning: Some objects will no longer be managed` is expected. If the
workspace's Terraform words the summary differently, what matters is the
headers and `0 to destroy`. **Stop and read both.**

**3b. Apply.** Merge #72, then from `main` apply each workspace, type
`yes` only for the same plan, and plan again:

```sh
git switch main && git pull
env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=cloudflare apply
env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=backblaze apply
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token tofu -chdir=$s plan -no-color | grep -E '^Plan:|^No changes'; done
```

On a `vcs=true` workspace, merging queues a VCS run instead: confirm it in
the TFC UI only if its headers and `Plan:` line match 3a exactly.

Nothing in Cloudflare, B2 or Doppler changes, only TFC's state. Then rebase
#73 onto `main`.

## 4. Apply foundation

```sh
cd ~/home-ops && git switch main && git pull
P="$BACKUP_DIR/foundation-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-5-plan.json
```

Expect the same as step 2. **Stop and read it**, then
`tf tf:apply STACK=foundation -- "$P" && rm -f "$P"`.

## 5. Apply this stack

Merge #2257, then:

```sh
git switch main && git pull
P="$BACKUP_DIR/truenas-$STAMP.tfplan"
tf tf:plan STACK=truenas -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=truenas PLAN="$P" EXPECT=p2-5-plan.json
```

Expect the same as step 2. **Stop and read it**, then
`tf tf:apply STACK=truenas -- "$P" && rm -f "$P"`.

Doppler now holds the new tokens and key; both TrueNAS hosts still hold the
old ones. Check the new values are new and live:

```sh
differ "TRUENAS_CLOUDFLARE_TOKEN is new" "$(dop TRUENAS_CLOUDFLARE_TOKEN | h)" "$(bak TRUENAS_CLOUDFLARE_TOKEN | h)"
differ "TRUENAS_BACKUP_CLOUDFLARE_TOKEN is new" "$(dop TRUENAS_BACKUP_CLOUDFLARE_TOKEN | h)" "$(bak TRUENAS_BACKUP_CLOUDFLARE_TOKEN | h)"
differ "TRUENAS_BACKUP_BUCKET key is new" "$(dopf TRUENAS_BACKUP_BUCKET application_key | h)" "$(bak TRUENAS_BACKUP_BUCKET application_key | h)"
same "bucket unchanged" "$(dopf TRUENAS_BACKUP_BUCKET bucket)" "$(bak TRUENAS_BACKUP_BUCKET bucket)"
same "endpoint unchanged" "$(dopf TRUENAS_BACKUP_BUCKET endpoint)" "$(bak TRUENAS_BACKUP_BUCKET endpoint)"
same "nas token active" "$(dop TRUENAS_CLOUDFLARE_TOKEN | cfverify)" active
same "backup token active" "$(dop TRUENAS_BACKUP_CLOUDFLARE_TOKEN | cfverify)" active
```

Expect `yes` ×7.

## 6. Paste the new values into TrueNAS, and prove each one

One value at a time: copy it, paste it, clear the clipboard, check it. The
menu paths are TrueNAS SCALE's; use your version's equivalent.

The hash checks run in each TrueNAS's shell (System > Shell, or SSH). Each
side prints a value's length and a 12-character hash prefix; compare them by
eye. Define the same helper on the laptop and in each TrueNAS's shell:

```sh
fp() { v=$(cat); printf 'len=%s sha=%s\n' "$(printf %s "$v" | wc -c | tr -d ' ')" "$(printf %s "$v" | sha256sum | cut -c1-12)"; unset v; }
```

TrueNAS releases name the fields differently, so the `jq` tries both
shapes. When the two sides differ, look at the TrueNAS side first:

- `len=0`: the field wasn't found. Look at `midclt call <query> | jq 'map(keys)'`
  (keys only, no values) and adjust the `jq`.
- A length that isn't the laptop's, and the value looks like a mask (for
  example `len=8`, from `********`): this TrueNAS **redacts** the field in
  its API, so the hash check can't work. That's not a `NO`. Skip it and rely
  on the functional checks below, which then get a decisive repeat in 9b,
  once the old credential is gone and only the new one can pass.
- The same length but another hash: a wrong paste, or the old value. Paste
  again.

**6a. Main TrueNAS, ACME token.**

```sh
dop TRUENAS_CLOUDFLARE_TOKEN | clip
```

Credentials > Certificates > ACME DNS-Authenticators > the Cloudflare one >
Edit: paste into **API Token**, Save. Then `clipclear`. Check:

```sh
# On the laptop:
dop TRUENAS_CLOUDFLARE_TOKEN | fp
# In the main TrueNAS's shell (put the authenticator's name in):
midclt call acme.dns.authenticator.query | jq -j --arg n '<authenticator name>' '.[] | select(.name == $n) | (.attributes // .) | .api_token // ""' | fp
```

The two lines match (or the field is redacted, above). Then **prove a DNS-01 issue works**, without
touching the certificate in use, against Let's Encrypt's staging directory
(no rate limits, untrusted certificate):

1. Credentials > Certificates > Certificate Signing Requests > Add: name
   `p2-5-staging-test`, common name and SAN `nas.rtrox.io`, Save.
2. On that CSR, **Create ACME Certificate**: name `p2-5-staging-test`, ACME
   Server Directory URI **Let's Encrypt Staging Directory**, authenticator
   for `nas.rtrox.io` the Cloudflare one, Save.
3. The job succeeds and a certificate issued by `(STAGING) ...` appears. A
   failure that mentions Cloudflare, the zone or a TXT record means the new
   token doesn't work: [rollback](#if-something-goes-wrong).
4. Delete the test certificate and its CSR.

**6b. Backup TrueNAS, ACME token.** As 6a, in the backup TrueNAS's UI and
shell, with `TRUENAS_BACKUP_CLOUDFLARE_TOKEN` and `backup.rtrox.io`. This
fixes its broken renewals (rtrox/terraform-record#53). Then look at its
in-use ACME certificate: if it's within its renew window or already expired,
TrueNAS renews it at its next daily check; confirm the new expiry the next
day.

**6c. Main TrueNAS, the B2 key.** Credentials > Backup Credentials > Cloud
Credentials > the B2 one > Edit. Copy, paste and clear each field in turn:

```sh
dopf TRUENAS_BACKUP_BUCKET application_key_id | clip   # paste into Key ID, then clipclear
dopf TRUENAS_BACKUP_BUCKET application_key | clip      # paste into Application Key, then clipclear
```

Click **Verify Credential** (it must succeed), then Save. Check:

```sh
# On the laptop:
for f in application_key_id application_key; do printf '%s %s\n' "$f" "$(dopf TRUENAS_BACKUP_BUCKET "$f" | fp)"; done
# In the main TrueNAS's shell (put the credential's name in):
for f in account key; do
  printf '%s %s\n' "$f" "$(midclt call cloudsync.credentials.query | jq -j --arg n '<credential name>' --arg f "$f" '.[] | select(.name == $n) | (.attributes // .provider) | .[$f] // ""' | fp)"
done
```

`account` matches `application_key_id`, `key` matches `application_key`. The
key ID isn't a secret, so even where TrueNAS redacts `key` it should show
`account` in full (and in the credential's edit form): a matching `account`
alone proves the new key is the one saved.
Then **a Cloud Sync dry run**: Data Protection > Cloud Sync Tasks > the task >
**Dry Run**. It must finish with no errors (a dry run lists and compares but
copies nothing). An authorization error means the new key doesn't work:
[rollback](#if-something-goes-wrong).

## 7. Wait

Leave the old tokens and key for one scheduled Cloud Sync run (its status
`SUCCESS` in Data Protection) and the backup TrueNAS's next daily renewal
check. Until step 9, the main TrueNAS can go back to its old token and key
from the backup.

## 8. Re-check, right before deleting

Both new stacks say `No changes.`, and step 6's checks still match:

```sh
cd ~/home-ops && git switch main && git pull
tf tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
tf tf:plan STACK=truenas -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
```

Re-run 6a's and 6c's shell hash checks on the main TrueNAS and 6b's on the
backup: an edit during the wait would show here.

## 9. Delete the old tokens and key

**9a. Plan #73** (rebased onto `main`) on its branch, each workspace
as in step 3a:

```text
cloudflare:
  # module.cf_api_token_truenas.cloudflare_api_token.token will be destroyed
  # module.cf_api_token_truenas_backup.cloudflare_api_token.token will be destroyed
Plan: 0 to add, 0 to change, 2 to destroy.
backblaze:
  # b2_application_key.old_truenas_backup will be destroyed
Plan: 0 to add, 0 to change, 1 to destroy.
```

Anything else: don't apply. **Stop and read both.**

**9b. Apply.** Merge #73 and apply each workspace from `main` as in
step 3b. Now only the new credentials exist, so these prove TrueNAS holds
them, even where step 6's hash checks were redacted:

- `dop TRUENAS_CLOUDFLARE_TOKEN | cfverify` and the same for the backup
  token, both `active`;
- on each TrueNAS, step 6a's staging certificate issue again (then delete
  it);
- on the main TrueNAS, **Verify Credential** and a Cloud Sync **Dry Run**.

A failure here is a paste that didn't take: Doppler holds the working value
(`cfverify` says so), so paste it again from Doppler and repeat the check.

## 10. Zero-diff gate and cleanup

All four say `No changes.`:

```sh
cd ~/home-ops && git switch main && git pull
tf tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
tf tf:plan STACK=truenas -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
cd ~/terraform-record && git switch main && git pull
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=$s plan -no-color | grep -E '^Plan:|^No changes'; done
```

The freeze ends here.

**Cleanup PR**: delete `imports.tf`, `p2-5-plan.json` and this file, and
foundation's `imports.tf` and `p2-5-plan*.json`. Its plans: `No changes.`
terraform-record's removed blocks, `truenas_write` aliases (keep the one
`minio` uses), `account.tf` and `modules/cf_token` go in its own cleanup.

Delete the `truenas-*` backup once the gate has held for a week.

## If something goes wrong

- **Step 1** only created a token nothing but this stack reads. Nothing to
  undo.
- **Step 3 (forget) misbehaves**: forgetting edits only TFC's state. Don't
  apply foundation or this stack. Either carry on (steps 4 and 5 adopt
  everything), or revert #72 and adopt the objects back in
  terraform-record with `import` blocks (the record IDs in `imports.tf` here;
  the bucket by its ID; the secrets as `hosts-at-home.prd.<NAME>`). Either
  plan must be imports only.
- **Step 4 or 5 fails partway**: what it did is in state. TrueNAS still holds
  the old values, which still work (except the backup's ACME token, already
  broken). Fix the cause, then plan, check and apply again.
- **A new value fails in TrueNAS (step 6)**:
  - Main TrueNAS: paste its old value back from the backup
    (`bak TRUENAS_CLOUDFLARE_TOKEN | clip`, or `bak TRUENAS_BACKUP_BUCKET
    application_key_id | clip` and `... application_key | clip`), then
    `clipclear`, and re-run that step's check. The old token and key work
    until step 9. Doppler keeps the new value; find out why it failed (a
    typo in the paste, a token that isn't `active`) before trying again.
  - Backup TrueNAS: what it held before is a deleted token, so going back
    to that gains nothing. Go forward: check `dop TRUENAS_BACKUP_CLOUDFLARE_TOKEN |
    cfverify` says `active`; if it doesn't, reissue it with
    `tf tf:plan STACK=foundation -- -replace='cloudflare_api_token.truenas_acme["backup.rtrox.io"]' -out=...`,
    check, apply, and paste again. `-replace` is right only here, for a
    token that already doesn't work; rotate a working one with a second
    entry (README.md). As a stopgap until step 9,
    `bak TRUENAS_BACKUP_CLOUDFLARE_TOKEN | clip` is terraform-record's old,
    still-live token.
- **After step 9** the old tokens and key are gone, so rollback is forward.
  If Doppler's value works (`cfverify`, or Verify Credential with it), paste
  it again. Only if Doppler's value itself is broken, reissue it
  (`-replace` in the stack that owns it: it no longer works, so nothing
  loses a working credential), its Doppler secret follows, and paste it.
- **Something destroyed**: nothing here plans a destroy before #73, the
  checker fails on any, and the bucket has `prevent_destroy`. Stop and look.
  Never edit state by hand.

## Follow-ups

- `pve.rtrox.io`'s record is still in terraform-record's `cloudflare` stack;
  the proxmox stack takes it (same moved-then-removed pattern).
- The NAS moves back to the house at 172.30.1.12 (its `moves_to`): an
  inventory edit, then a plan and apply of this stack from the laptop (it's
  `laptop-only`: nothing plans it for you).
- The `nas.rtrox.io` comment (`Main TrueNAs`) keeps its live typo; fix it in
  its own change (an in-place update).
- Narrow the B2 key to what Cloud Sync needs, and give it a key name of its
  own (README.md).
