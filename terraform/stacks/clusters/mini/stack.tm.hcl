stack {
  name        = "clusters/mini"
  description = "What the mini cluster needs from outside itself: its API record, its Cloudflare Tunnel, and its volsync and CNPG off-site buckets"
  id          = "734e9e1e-effe-4582-9dd6-ed44ac0fb571"

  # ci-skip for now (see README.md): CI has no
  # credentials for it yet, so CI doesn't plan, apply or drift-check it, and
  # the owner applies it from the laptop. Unlike laptop-only, the state keeps
  # the shared passphrase. A later PR swaps the tag for ci-apply, once CI can
  # plan it (README.md, "Before tagging this stack ci-apply").
  tags = ["ci-skip"]

  # api_records.tf reads it; an inventory change must re-plan the stack.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers      = ["backblaze", "cloudflare", "garage"]
  doppler_writes = ["k8s-at-home/min"]

  # Its own Cloudflare token (foundation's mini_token.tf): Zone Read and DNS
  # Write on rtrox.io, Cloudflare Tunnel Write on the account.
  provider_keys = { cloudflare = "CLOUDFLARE_MINI_TOKEN" }
}
