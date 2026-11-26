# truenas

What the two TrueNAS hosts need from outside themselves: their A records
(`nas.rtrox.io`, `backup.rtrox.io`, from `inventory/hosts.yaml`) and the main
TrueNAS's Cloud Sync bucket `nas-rtrox-io-truenas-backup`, with its key in
Doppler `hosts-at-home/prd` (`TRUENAS_BACKUP_BUCKET`). Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-5.
The hosts' ACME DNS-01 tokens (`TRUENAS_CLOUDFLARE_TOKEN`,
`TRUENAS_BACKUP_CLOUDFLARE_TOKEN`) live in `foundation`
(`truenas_acme_tokens.tf`), so this stack can't mint tokens.

Tagged `laptop-only`: CI never plans, applies or drift-checks it, and its
state is encrypted with the owner's own passphrase
(`TOFU_STATE_PASSPHRASE_LAPTOP`, which `task tf:*` picks for laptop-only
stacks). Plan it after any inventory edit to either host: nothing else will.

## Moving to the locked bucket (phase 4)

`module.nas_backup_locked_bucket` replaces `nas-rtrox-io-truenas-backup`:
same contents, plus Object Lock (governance, 45 days) and a key that can't
delete. That's what lets this stack's state, which holds the key, be read by
CI. `TRUENAS_BACKUP_BUCKET` points at the new bucket once applied.

1. **Apply** this stack: 2 to add (the bucket and its key), 1 to change (the
   Doppler secret), 0 to destroy.
2. **Copy server-side** with the `terraform-backblaze` key (account-wide, no
   bypassGovernance). Both buckets are in one account, so rclone uses B2's
   server-side copy: no download or upload, and file mod times are kept, so
   Cloud Sync sees nothing to upload afterwards.

   ```sh
   export RCLONE_CONFIG_B2_TYPE=b2
   export RCLONE_CONFIG_B2_ACCOUNT="$(doppler secrets get BACKBLAZE_APPLICATION_KEY_ID -p tf-at-home -c prd --plain)"
   export RCLONE_CONFIG_B2_KEY="$(doppler secrets get BACKBLAZE_APPLICATION_KEY -p tf-at-home -c prd --plain)"
   rclone copy B2:nas-rtrox-io-truenas-backup B2:nas-rtrox-io-truenas-backup-locked \
     --b2-copy-cutoff 4G --checkers 32 --transfers 32 --progress
   rclone check B2:nas-rtrox-io-truenas-backup B2:nas-rtrox-io-truenas-backup-locked --size-only --one-way
   ```
3. **Switch Cloud Sync**: a new cloud credential from `TRUENAS_BACKUP_BUCKET`
   (Verify Credential), the task's credential and bucket changed to it, then
   a Dry Run: it should list nothing (or almost nothing) to transfer. Then one
   real run.
4. **Retire the old bucket** in a later PR, once a real run has succeeded:
   forget it (`removed`; the module's `prevent_destroy` refuses a destroy)
   and empty and delete it by hand in B2. Then the stack can move to CI.

## Rotating a credential

Nothing here reaches TrueNAS by itself: the owner pastes each value into the
TrueNAS UI. So a rotation must keep the old value valid until the new one is
pasted in and proven. **Never `-replace`**: that deletes the old credential
in the same apply, before TrueNAS has the new one. Add a second one instead:

1. **Add**: a second entry (a new key) next to the current one, and point the
   Doppler secret at it. For the B2 key, a second key under
   `module.nas_backup_bucket`'s `keys`, with `legacy_api = true` while
   TrueNAS's rclone is older than 1.73 (it refuses the key otherwise), and
   `local.nas_backup_key` set to its name. For an ACME token, a second entry in foundation's
   `truenas_acme_tokens` and the host's `token` in `truenas_acme_hosts`.
   Apply: one created, the Doppler secret updated, nothing deleted.
2. **Paste and prove** it in TrueNAS:
   - an ACME token: issue a throwaway certificate for the host's name with
     that authenticator against Let's Encrypt's staging directory (a CSR,
     then Create ACME Certificate), then delete it. The certificate in use
     is untouched;
   - the B2 key: Verify Credential on the cloud credential, then a Dry Run
     of the Cloud Sync task.
3. **Remove** the old entry. Apply: the old one deleted.

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

## Known follow-ups

- The NAS moves back to the house at 172.30.1.12 (its `moves_to`): an
  inventory edit, then a plan and apply of this stack from the laptop.
- The `nas.rtrox.io` comment (`Main TrueNAs`) keeps its live typo; fix it in
  its own change (an in-place update).
- The backup TrueNAS is off until May 2027: paste its ACME token then
  (rtrox/terraform-record#53).
- Narrow the B2 key to what Cloud Sync needs, as a second key (above).

## Before moving this stack to CI

Planned, once it's safe. It's `laptop-only` because its state holds the Cloud Sync B2
key, which has the old default capabilities (`deleteFiles` included) on a
bucket without Object Lock. A stolen copy could delete the off-site backup.
Moving it to `ci-apply` would mean the shared passphrase (CI can decrypt that
state) and a state migration to re-encrypt it. Before that:

- Narrow the key to what Cloud Sync needs, or protect the bucket another way.
- **Cloudflare**: `CLOUDFLARE_TRUENAS_TOKEN` in `tf-at-home/ci` holding the
  read-only CI token, and in `ci-apply` the real one (foundation adds both
  `doppler_secret`s then).
- **B2**: a read-only key for plans, as clusters/mini's README describes.
- **Doppler**: a read token for plans. One on `hosts-at-home/prd` reads every
  host secret there (the Proxmox API token among them), so give this stack's
  secrets their own config first, as clusters/mini's README does with
  `k8s-at-home/min-ci` (a config for secrets written by a stack CI plans).
