stack {
  name        = "truenas"
  description = "The two TrueNAS hosts' A records, and the main TrueNAS's cloud-sync B2 bucket and key"
  id          = "b971bcc6-8fdc-431f-9266-ca7eb58d9ffb"

  # Applied from the owner's laptop only, like foundation: CI never plans,
  # applies or drift-checks it, and task tf:* encrypts its state with
  # TOFU_STATE_PASSPHRASE_LAPTOP, which CI doesn't hold. The state holds the
  # Cloud Sync B2 key, which can delete files on a bucket without Object Lock,
  # so CI must not be able to decrypt it (README.md).
  tags = ["laptop-only"]

  # records.tf builds both A records from it (each host's dns_name and
  # address). An address edit, such as the NAS's renumber at its move
  # (`moves_to`), changes the live record at the next laptop apply. There's no
  # drift check for a laptop-only stack, so plan this stack after any edit to
  # nas.rtrox.io or backup.rtrox.io in the inventory.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers      = ["backblaze", "cloudflare", "truenas"]
  doppler_writes = ["hosts-at-home/prd"]

  # Its own Cloudflare token (foundation's truenas_token.tf): Zone Read and DNS
  # Write on rtrox.io, nothing else. The TrueNAS ACME tokens are foundation's
  # (truenas_acme_tokens.tf), so this stack can't mint tokens.
  provider_keys = { cloudflare = "CLOUDFLARE_TRUENAS_TOKEN" }
}
