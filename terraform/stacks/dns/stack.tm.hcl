stack {
  name        = "dns"
  description = "Cloudflare zones, their WAF rulesets and zone-level records (mail, verification)"
  id          = "b7d34ba7-742f-4a0a-89e1-84f3eb05385b"

  # No tags yet: this stack is applied from the laptop until its move from
  # terraform-record passes the zero-diff gate (MIGRATION.md). A follow-up PR
  # then tags it ["ci-apply"] (a plan with a destroy, replace or forget then waits
  # for approval on its own). Never tag it ci-apply in the PR that
  # adds the imports: merging would apply them.
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare"]
}
