stack {
  name        = "truenas"
  description = "The two TrueNAS hosts' A records, and the main TrueNAS's cloud-sync B2 bucket and key"
  id          = "b971bcc6-8fdc-431f-9266-ca7eb58d9ffb"

  # ci-skip for now (see README.md): CI has no credentials for it yet, so CI
  # doesn't plan, apply or drift-check it, and the owner applies it from the
  # laptop. Unlike laptop-only, the state keeps the shared passphrase. A later
  # PR swaps the tag for ci-apply, once CI can plan it.
  tags = ["ci-skip"]

  # records.tf reads it; an inventory change must re-plan the stack.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers      = ["backblaze", "cloudflare"]
  doppler_writes = ["hosts-at-home/prd"]

  # Its own Cloudflare token (foundation's truenas_token.tf): Zone Read and DNS
  # Write on rtrox.io, nothing else. The TrueNAS ACME tokens are foundation's
  # (truenas_acme_tokens.tf), so this stack can't mint tokens.
  provider_keys = { cloudflare = "CLOUDFLARE_TRUENAS_TOKEN" }
}
