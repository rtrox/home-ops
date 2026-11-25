stack {
  name        = "curt"
  description = "Storage for curt, the URL shortener on Cloudflare Workers (github.com/rtrox/curt)"
  id          = "2f817db8-b7d1-47fd-9e88-ad9e81c56c90"

  # ci-skip for now: CI has no Cloudflare token for it, so the owner applies it
  # from the laptop. The state keeps the shared passphrase.
  tags = ["ci-skip"]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare"]

  # Its own Cloudflare token (foundation's curt_tokens.tf).
  provider_keys = { cloudflare = "CLOUDFLARE_CURT_TOKEN" }
}
