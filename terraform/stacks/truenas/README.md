# truenas

What the two TrueNAS hosts need from outside themselves: their A records
(`nas.rtrox.io`, `backup.rtrox.io`, from `inventory/hosts.yaml`) and the main
TrueNAS's Cloud Sync bucket `nas-rtrox-io-truenas-backup`, with its key in
Doppler `hosts-at-home/prd` (`TRUENAS_BACKUP_BUCKET`). Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-5.
The hosts' ACME DNS-01 tokens (`TRUENAS_CLOUDFLARE_TOKEN`,
`TRUENAS_BACKUP_CLOUDFLARE_TOKEN`) live in `foundation`
(`truenas_acme_tokens.tf`), so this stack can't mint tokens.

Nothing here reaches TrueNAS by itself: the owner pastes each value into the
TrueNAS UI. So replacing the key (or a token in foundation) means pasting the
new value in and proving it before the old one is deleted:

- **An ACME token**: issue a throwaway certificate for the host's name with
  that authenticator against Let's Encrypt's staging directory (a CSR, then
  Create ACME Certificate), then delete it. The certificate in use is
  untouched.
- **The B2 key**: Verify Credential on the cloud credential, then a Dry Run
  of the Cloud Sync task.

Replacing a B2 key in place (`-replace`) deletes the old key as soon as the
new one exists (the module has no create-before-destroy), so Cloud Sync fails
until the new key is pasted in. Prefer adding a second key under `keys`,
pasting it, then removing the first.

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

## Before tagging this stack ci-apply

The stack is tagged `ci-skip`. The PR that swaps it for `ci-apply` needs:

- **Cloudflare**: `CLOUDFLARE_TRUENAS_TOKEN` in `tf-at-home/ci` holding the
  read-only CI token, and in `ci-apply` the real one (foundation adds both
  `doppler_secret`s then).
- **B2**: a read-only key for plans, as clusters/mini's README describes.
- **Doppler**: a read token for plans. One on `hosts-at-home/prd` reads every
  host secret there (the Proxmox API token among them), so give this stack's
  secrets their own config first, as clusters/mini's README plans for
  `k8s-at-home/min_tf`.
- **State**: it uses the shared passphrase, so CI could decrypt it once it
  exists. It holds the B2 key, which has the old default capabilities
  (`deleteFiles` included, no Object Lock). Narrow the key to what Cloud Sync
  needs before CI can read it.
