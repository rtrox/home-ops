# truenas

What the two TrueNAS hosts need from outside themselves: their A records
(`nas.rtrox.io`, `backup.rtrox.io`, from `inventory/hosts.yaml`) and the main
TrueNAS's Cloud Sync bucket `nas-rtrox-io-truenas-backup-locked`, with its key in
Doppler `hosts-at-home/prd` (`TRUENAS_BACKUP_BUCKET`). Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-5.
The hosts' ACME DNS-01 tokens (`TRUENAS_CLOUDFLARE_TOKEN`,
`TRUENAS_BACKUP_CLOUDFLARE_TOKEN`) live in `foundation`
(`truenas_acme_tokens.tf`), so this stack can't mint tokens. It also runs
Garage (S3, replacing MinIO) as a TrueNAS custom app, with its datasets and the
`s3.nas.rtrox.io` record (see "Garage (S3)").

Tagged `ci-apply`: CI plans it on PRs, applies it on merge and checks it for
drift nightly, with the shared state passphrase (see "In CI" below).

## The off-site bucket

`module.nas_backup_locked_bucket` has Object Lock (governance, 45 days) and a
Cloud Sync key that can't delete, so a leaked key can't destroy the copy. That's what
lets this stack's state, which holds the key, be read by CI. `cloud_sync.tf`
writes the key to TrueNAS and manages task 1 (Remote Encryption stays in the
UI; see that file).

It replaced `nas-rtrox-io-truenas-backup` in phase 4: a server-side copy
(rclone, B2 to B2), Cloud Sync switched over, then the old key destroyed and
the bucket forgotten and purged by hand (Nov 2026). Two trade-offs came with it:
- **History:** a hidden or overwritten version is kept 30 days (45 within
  the lock), not forever as before. The copy took current files only.
- **Reads:** the key keeps `readFiles` (rclone needs it), so whoever reads this
  state can download the backup. That's why the Cloud Sync task's Remote
  Encryption matters: it was confirmed on before the stack moved to CI, so
  those downloads are ciphertext.

## Garage (S3)

`garage.tf`: Garage v2 (replaces MinIO, migration phase 4) as a TrueNAS custom
app on the main NAS: one node, replication factor 1, `garage server
--single-node` (it lays itself out, so the layout isn't Terraform's).
`duplicacy.tf` makes Duplicacy's bucket on it (below); mini's buckets are in
`clusters/mini`.

- **Endpoint:** `http://s3.nas.rtrox.io:3900` (region `garage`); the A record
  points at the NAS's inventory address. The admin API and `/metrics` are on
  `:3903`. RPC (`:3901`) is inside the container and not published.
- **Storage:** two datasets, both `prevent_destroy`: the data on
  `rusty/garage` (HDD pool), the LMDB metadata on `zippy/garage-meta` (SSD
  pool). They are bind mounts, not ixVolumes, so deleting the app deletes no
  data. The app runs as 568:568 (the APPS dataset preset).
- **Config:** `garage.toml` is inline in the compose (`configs:` with
  `content:`), with no secrets. The RPC secret (`random_bytes`, 32 bytes hex; not `random_id`, whose id would print it) and
  the admin and metrics tokens (`random_password`) are env vars in the compose
  and are written to Doppler `hosts-at-home/prd` (`GARAGE_RPC_SECRET`,
  `GARAGE_ADMIN_TOKEN`, `GARAGE_METRICS_TOKEN`). They are in this stack's
  state too (encrypted, but CI can read it).
- **Updates:** a compose edit (a new image digest, a config change) updates the
  app in place; only `app_name`, `catalog_app`, `train` and `version` would
  replace it, and only `app_name` is set (never rename it). Replacing the app is safe for data (bind mounts)
  but not for uptime. **Plan after any Garage upgrade**, and check a major
  upgrade's notes for a metadata migration first.
- **Rotating a secret:** `task tf:apply STACK=truenas -- -replace=random_password.garage_admin_token`
  (or the metrics token, or `random_bytes.garage_rpc_secret`). On this single
  node an RPC-secret rotation only restarts the container; with more nodes,
  every node must change together.
- **Durability:** one copy, so `metadata_fsync`, `data_fsync` and a 6-hourly
  metadata snapshot (`metadata_auto_snapshot_interval`) are on. After an
  unclean shutdown that corrupts LMDB, restore the newest snapshot from
  `metadata_dir/snapshots` (Garage's recovery docs).

- **Duplicacy's bucket:** `duplicacy.tf` makes `rtrox-duplicacy` (MinIO's
  name) through the `garage-store` module: one key of the same name with read
  and write on that bucket only (never owner), and writes
  `{application_key_id, application_key, endpoint, bucket, region}` to
  `hosts-at-home/prd` as `DUPLICACY_LOCAL_BUCKET` (endpoint
  `http://s3.nas.rtrox.io:3900`, region `garage`). Nothing reads it yet:
  Duplicacy keeps using `RTROX_DUPLICACY` (the MinIO key, written by
  terraform-record; this stack never touches it) until its cutover. The
  bucket is `prevent_destroy`, and a destroyed key can't be re-imported, so
  rotate a key by adding a second one.
- **The garagehq provider and a fresh apply:** the provider configures
  itself with only a host and a token (it makes no API call until a resource
  is read or written), so a plan with no Garage in state works, and the
  provider being configured before Garage exists isn't a failure by itself.
  But on a first apply, or a rebuild after a disaster, the Garage resources
  (`module.garage_duplicacy`) need the admin API up, which the same stack
  creates: they `depends_on` `truenas_app.garage`, so Terraform makes the app
  first and then the bucket, but the app takes a moment to start listening
  and the token has to exist. Do it in two steps: `task tf:apply STACK=truenas
  -- -target=truenas_app.garage` (and the records it needs), wait until
  `http://s3.nas.rtrox.io:3903/health` answers, then a plain apply. The
  scoped CI plan token (below) lives inside Garage, so a rebuilt Garage has
  none: make it again, then update `tf-at-home/ci`. With the NAS down, plan
  the rest with `-target`.
- **A garage plan needs the runner to reach `nas.rtrox.io:3903`:** the CI
  runner's firewall change is its own PR (#2352) and must be applied first,
  or the plan and apply jobs fail on the Garage resources.

## Rotating a credential

The Cloud Sync B2 key is written to TrueNAS by this stack (`cloud_sync.tf`):
to rotate it, add a second key under `module.nas_backup_locked_bucket`'s
`keys` and point `local.nas_backup_key` at it. One apply replaces the TrueNAS
credential (the new one is created first, the task moves to it, then the old
one goes; it's named after the key ID, so names don't clash), and a later one
removes the old key. Editing the key by hand in TrueNAS isn't noticed: the
credential is only compared by key ID (`cloud_sync.tf`). The rest of this
section covers the ACME tokens, which still reach TrueNAS by hand.

Nothing else here reaches TrueNAS by itself: the owner pastes each ACME token into the
TrueNAS UI. So a rotation must keep the old value valid until the new one is
pasted in and proven. **Never `-replace`**: that deletes the old credential
in the same apply, before TrueNAS has the new one. Add a second one instead:

1. **Add**: a second entry in foundation's `truenas_acme_tokens`, and point
   the host's `token` in `truenas_acme_hosts` at it. Apply: one created, the
   Doppler secret updated, nothing deleted.
2. **Paste and prove** it in TrueNAS: issue a throwaway certificate for the
   host's name with that authenticator against Let's Encrypt's staging
   directory (a CSR, then Create ACME Certificate), then delete it. The
   certificate in use is untouched.
3. **Remove** the old entry. Apply: the old one deleted.

For the B2 key, the new key keeps `legacy_api = true` while TrueNAS's rclone
is older than 1.73 (it refuses the key otherwise). After the first apply,
Verify Credential and a Dry Run of the task before removing the old key.

Duplicacy's MinIO bucket (`RTROX_DUPLICACY`) stays in terraform-record until
the Duplicacy cutover; its Garage bucket is `duplicacy.tf`. The architecture's `host` module (records, ACME token, backup
bucket) is extracted later; the resources here are keyed by host so `moved`
blocks can carry them into it.

## Credentials (the laptop's, `prd`; CI's are under "In CI")

| Provider | Key | Can |
| --- | --- | --- |
| Cloudflare | `CLOUDFLARE_TRUENAS_TOKEN` (foundation's `truenas_token.tf`) | Zone Read and DNS Write on rtrox.io |
| B2 | the shared provider key | everything but `bypassGovernance`; `writeKeys` is account-wide in B2, so no narrower key can create this bucket's keys |
| Doppler | `DOPPLER_TRUENAS_WRITE_TOKEN` | read and write `hosts-at-home/prd` |
| TrueNAS | `TRUENAS_API_KEY` | the full API key (user terraform, Local Administrator) |

## Known follow-ups

- The NAS moves back to the house at 172.30.1.12 (its `moves_to`): an
  inventory edit; CI plans and applies it.
- The `nas.rtrox.io` comment (`Main TrueNAs`) keeps its live typo; fix it in
  its own change (an in-place update).
- The backup TrueNAS is off until May 2027: paste its ACME token then
  (rtrox/terraform-record#53).

## In CI

Moved from `laptop-only` to `ci-apply` in Nov 2026. CI's credentials:

| | Plans (`tf-at-home/ci`) | Applies (`ci-apply`) |
| --- | --- | --- |
| TrueNAS | `TRUENAS_API_KEY`: user terraform-ro (Read-Only Administrator); its placeholder secrets don't drift (`cloud_sync.tf`); the Garage app's compose reads back unredacted (checked with `CI_KEYS` after the first apply) | the full key (a Doppler reference to `prd`) |
| B2 | `home-ops-ci-plan-readonly`: list and read buckets, their settings and keys, no files | the account key (a reference to `prd`) |
| Cloudflare | `CLOUDFLARE_TRUENAS_TOKEN` = the read-only CI token (foundation's `truenas_ci.tf`) | the real token |
| Garage | `GARAGE_ADMIN_TOKEN`: a read-only scoped admin token (`GetBucketInfo`, `GetKeyInfo` only), made by hand inside Garage | the full admin token (a Doppler reference to `hosts-at-home/prd`) |
| Doppler | `DOPPLER_TRUENAS_WRITE_TOKEN`, read on `hosts-at-home/prd` | read/write |

- **Gate:** `tf-ci.sh`'s `TF_GATE_ON_CREATE` sends a plan that creates
  `truenas_cloud_sync` to `tofu-apply-gated` (a create would be unencrypted;
  see `cloud_sync.tf`). Don't approve one.
- **Never the read-only TrueNAS key for an apply:** a state saved after its
  refresh would hold the placeholder, and the next rename would send it.
- **Known gap, accepted:** the plan token on `hosts-at-home/prd` reads every
  host's secrets (the Proxmox API token among them), so every PR plan job can.
- **Known gap, accepted:** the runner's job firewall lets every job reach
  `nas.rtrox.io:443` (`github_runner_allowed_lan`), so a PR job can reach the
  TrueNAS web UI and API unauthenticated (and try passwords), and the
  read-only key it gets sees the whole NAS config.
- **Known gap, accepted:** the Garage secrets are in this stack's state, which
  PR plan jobs decrypt, and in `hosts-at-home/prd`, which their read token
  reads. The runner's firewall change for `nas.rtrox.io:3903` (the garagehq
  provider's admin API) is PR #2352, a prerequisite for planning this stack.
- **Known gap, accepted:** the plan's Garage token holds `GetKeyInfo`, and
  Garage scopes are per endpoint, not per parameter. The provider's refresh
  never sends `showSecretKey` (only an import does), so a plan doesn't read
  any key's secret, but a PR job's own code could call `GetKeyInfo` with
  `showSecretKey=true` and read every key's secret (Duplicacy's, mini's). The
  admin API is plain HTTP on the LAN as well.
- Test what CI's keys see from the laptop with `task tf:plan STACK=truenas
  CI_KEYS="BACKBLAZE_APPLICATION_KEY_ID BACKBLAZE_APPLICATION_KEY
  TRUENAS_API_KEY GARAGE_ADMIN_TOKEN CLOUDFLARE_TRUENAS_TOKEN DOPPLER_TRUENAS_WRITE_TOKEN"`.

**The state's re-encryption** (once, before the merge that tagged it
`ci-apply`), from that branch, where `task tf:*` already picks the shared
passphrase. Two applies with extra key providers in `TF_ENCRYPTION`, which
OpenTofu merges into the code's `encryption` block:

1. Save under a temporary key provider `next` (the shared passphrase), reading
   with `laptop` (the laptop passphrase, aliased to the metadata key the state
   was written under, `key_provider.pbkdf2.main`). The fallback can't simply be
   the laptop key under `main`'s metadata key: the primary method registers
   that key before it fails, and the fallback's then collides ("Duplicate
   metadata key").
2. Save under `main` (the code's), reading with `next`.

Each apply needs a change to save the state (an unchanged state isn't written):
the first creates `terraform_data.state_encryption`, the second replaces it.
Earlier versions in the B2 state history stay encrypted with
`TOFU_STATE_PASSPHRASE_LAPTOP`, which foundation still uses. Both passphrases
are base64, so they're safe inside the HCL strings.

```sh
(
  laptop="$(doppler secrets get TOFU_STATE_PASSPHRASE_LAPTOP -p tf-at-home -c prd --plain)"
  shared="$(doppler secrets get TOFU_STATE_PASSPHRASE -p tf-at-home -c prd --plain)"
  next_kp="key_provider \"pbkdf2\" \"next\" { passphrase = \"$shared\" }
method \"aes_gcm\" \"next\" { keys = key_provider.pbkdf2.next }"
  unset shared

  # 1: laptop -> next
  export TF_ENCRYPTION="$next_kp
key_provider \"pbkdf2\" \"laptop\" {
  passphrase               = \"$laptop\"
  encrypted_metadata_alias = \"key_provider.pbkdf2.main\"
}
method \"aes_gcm\" \"laptop\" { keys = key_provider.pbkdf2.laptop }
state {
  enforced = true
  method   = method.aes_gcm.next
  fallback { method = method.aes_gcm.laptop }
}
plan {
  enforced = true
  method   = method.aes_gcm.next
  fallback { method = method.aes_gcm.laptop }
}"
  unset laptop
  task tf:apply STACK=truenas || exit 1

  # 2: next -> main
  export TF_ENCRYPTION="$next_kp
state {
  enforced = true
  method   = method.aes_gcm.main
  fallback { method = method.aes_gcm.next }
}
plan {
  enforced = true
  method   = method.aes_gcm.main
  fallback { method = method.aes_gcm.next }
}"
  task tf:apply STACK=truenas -- -replace=terraform_data.state_encryption
)
```

Pass 1 should plan 1 to add (the marker), pass 2 1 to add and 1 to destroy
(the marker's replace), nothing else. If pass 2 fails, the state is readable
with pass 2's `TF_ENCRYPTION`; rerun it. Then, without `TF_ENCRYPTION`,
`task tf:plan STACK=truenas` must say No changes.
