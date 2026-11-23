stack {
  name        = "clusters/mini"
  description = "What the mini cluster needs from outside itself: its API record, its Cloudflare Tunnel, the external-dns and cert-manager tokens, and its volsync and CNPG off-site buckets"
  id          = "734e9e1e-effe-4582-9dd6-ed44ac0fb571"

  # No tags yet: applied from the owner's laptop during the move from
  # terraform-record (MIGRATION.md). `ci-apply` comes in its own PR after the
  # zero-diff gate, once CI has credentials that can plan it (MIGRATION.md,
  # "CI"). Not laptop-only: that tag would encrypt this state with the laptop
  # passphrase, and dropping it later means re-encrypting.

  # api_records.tf reads it; an inventory change must re-plan the stack.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers      = ["backblaze", "cloudflare"]
  doppler_writes = ["k8s-at-home/min"]

  # Its own Cloudflare token (foundation's mini_token.tf): Zone Read and DNS
  # Write on rtrox.io, Cloudflare Tunnel Write on the account, API Tokens
  # Write on the owner's user. In tf-at-home/ci the same key holds the
  # read-only CI token.
  provider_keys = { cloudflare = "CLOUDFLARE_MINI_TOKEN" }
}
