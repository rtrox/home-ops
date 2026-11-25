stack {
  name        = "curt"
  description = "Storage for curt, the URL shortener on Cloudflare Workers (github.com/rtrox/curt)"
  id          = "2f817db8-b7d1-47fd-9e88-ad9e81c56c90"

  # ci-skip: its Cloudflare token can deploy Workers (foundation's
  # curt_tokens.tf), so CI doesn't get it and the owner applies from the laptop.
  # The state keeps the shared passphrase.
  tags = ["ci-skip"]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare"]

  # Its own Cloudflare token (foundation's curt_tokens.tf).
  provider_keys = { cloudflare = "CLOUDFLARE_CURT_TOKEN" }
}
