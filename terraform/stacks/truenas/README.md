# truenas

What the two TrueNAS hosts need from outside themselves: their A records
(`nas.rtrox.io`, `backup.rtrox.io`, from `inventory/hosts.yaml`) and the main
TrueNAS's Cloud Sync bucket `nas-rtrox-io-truenas-backup-locked`, with its key in
Doppler `hosts-at-home/prd` (`TRUENAS_BACKUP_BUCKET`). Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-5.
The hosts' ACME DNS-01 tokens (`TRUENAS_CLOUDFLARE_TOKEN`,
`TRUENAS_BACKUP_CLOUDFLARE_TOKEN`) live in `foundation`
(`truenas_acme_tokens.tf`), so this stack can't mint tokens.

Tagged `laptop-only`: CI never plans, applies or drift-checks it, and its
state is encrypted with the owner's own passphrase
(`TOFU_STATE_PASSPHRASE_LAPTOP`, which `task tf:*` picks for laptop-only
stacks). Plan it after any inventory edit to either host: nothing else will.

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
  state can download the backup. Before the stack drops `laptop-only`, confirm
  the Cloud Sync task has Remote Encryption on.

## Rotating a credential

The Cloud Sync B2 key is written to TrueNAS by this stack (`cloud_sync.tf`):
to rotate it, add a second key under `module.nas_backup_locked_bucket`'s
`keys` and point `local.nas_backup_key` at it. One apply replaces the TrueNAS
credential (the new one is created first, the task moves to it, then the old
one goes; it's named after the key ID, so names don't clash), and a later one
removes the old key. **Not yet**: that replace needs the trigger the next change
adds (`cloud_sync.tf`); until then, don't rotate. Editing the key by hand in
TrueNAS isn't noticed: the credential is only compared by key ID. The rest of this
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

The duplicacy bucket stays on MinIO, in terraform-record, until phase 4's
Garage. The architecture's `host` module (records, ACME token, backup
bucket) is extracted later; the resources here are keyed by host so `moved`
blocks can carry them into it.

## Credentials

| Provider | Key | Can |
| --- | --- | --- |
| Cloudflare | `CLOUDFLARE_TRUENAS_TOKEN` (foundation's `truenas_token.tf`) | Zone Read and DNS Write on rtrox.io |
| B2 | the shared provider key | everything but `bypassGovernance`; `writeKeys` is account-wide in B2, so no narrower key can create this bucket's keys |
| Doppler | `DOPPLER_TRUENAS_WRITE_TOKEN` | read and write `hosts-at-home/prd` |
| TrueNAS | `TRUENAS_API_KEY` | the full API key; a read-only one is in Doppler for CI plans later |

## Known follow-ups

- The NAS moves back to the house at 172.30.1.12 (its `moves_to`): an
  inventory edit, then a plan and apply of this stack from the laptop.
- The `nas.rtrox.io` comment (`Main TrueNAs`) keeps its live typo; fix it in
  its own change (an in-place update).
- The backup TrueNAS is off until May 2027: paste its ACME token then
  (rtrox/terraform-record#53).

## Before moving this stack to CI

Planned. The Cloud Sync key in its state can no longer delete (the locked
bucket, above), so that's no longer the reason it's `laptop-only`. Moving it
to `ci-apply` means the shared passphrase (CI can decrypt that state) and a
state migration to re-encrypt it. Before that:

- **CI gate** (done): `tf-ci.sh`'s `TF_GATE_ON_CREATE` sends a plan that
  creates `truenas_cloud_sync` to `tofu-apply-gated` (a create would be
  unencrypted; see `cloud_sync.tf`). Don't approve one.
- **TrueNAS**: the read-only API key in `tf-at-home/ci` for plans (its
  placeholder secrets don't drift: `cloud_sync.tf` ignores them), the full
  one in `ci-apply`. Never the read-only key for an apply: a state saved after
  its refresh would hold the placeholder, and the next rename would send it.
- **Cloudflare**: `CLOUDFLARE_TRUENAS_TOKEN` in `tf-at-home/ci` holding the
  read-only CI token, and in `ci-apply` the real one (foundation adds both
  `doppler_secret`s then).
- **B2**: a read-only key for plans, as clusters/mini's README describes.
- **Doppler**: a read token for plans. One on `hosts-at-home/prd` reads every
  host secret there (the Proxmox API token among them), so give this stack's
  secrets their own config first, as clusters/mini's README does with
  `k8s-at-home/min-ci` (a config for secrets written by a stack CI plans).
