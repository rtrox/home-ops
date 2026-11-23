stack {
  name        = "dns"
  description = "Cloudflare zones, their WAF rulesets, zone-level records (mail, verification) and parked host records"
  id          = "b7d34ba7-742f-4a0a-89e1-84f3eb05385b"

  # Applied by CI on merge (terraform-apply.yaml). A plan with a destroy,
  # replace or forget waits for the owner's approval in tofu-apply-gated;
  # anything else applies straight away.
  tags = ["ci-apply"]

  # host_records.tf reads it; an inventory change must re-plan the stack.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare"]

  # Its own Cloudflare token (foundation's dns_token.tf): Zone Read/Write,
  # DNS Write and Zone WAF Write on the account's zones, nothing else. In
  # tf-at-home/ci the same key holds the read-only CI token.
  provider_keys = { cloudflare = "CLOUDFLARE_DNS_TOKEN" }
}
