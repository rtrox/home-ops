stack {
  name        = "clusters/mini-services"
  description = "What runs on mini and is configured from outside it: pocket-id's groups and OIDC clients"
  id          = "4b3b1902-390d-4e2a-a156-32cc83efad83"

  # ci-apply: CI plans it on PRs (read-only credentials) and applies it on
  # merge. pocket-id's API keys have no scopes, so the POCKETID_API_TOKEN in
  # tf-at-home/ci is an admin key, read by every PR plan job (the owner
  # accepted that). Client secrets are written to k8s-at-home/min-ci, so they
  # end up in this stack's state too.
  tags = ["ci-apply"]

  # infra.tf reads every cluster-apps/mini/*/*/infra.yaml. Terramate's `watch`
  # takes no globs, so terraform-plan.yaml adds this stack to a PR's changed
  # stacks when one of those files changed (tf_infra_changed in tf-ci.sh).
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["pocketid"]

  # Client secrets of the clients declared in infra.yaml. The read-only token
  # in tf-at-home/ci plans; ci-apply and prd hold the read/write one.
  doppler_writes = ["k8s-at-home/min-ci"]
}
