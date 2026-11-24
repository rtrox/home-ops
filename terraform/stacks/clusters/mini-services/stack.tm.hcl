stack {
  name        = "clusters/mini-services"
  description = "What runs on mini and is configured from outside it: pocket-id's groups and OIDC clients"
  id          = "4b3b1902-390d-4e2a-a156-32cc83efad83"

  # ci-skip while it moves in from terraform-record (MIGRATION.md): CI has no
  # pocket-id key, so CI doesn't plan, apply or drift-check it, and the owner
  # applies it from the laptop. Unlike laptop-only, the state keeps the shared
  # passphrase. A later PR swaps the tag for ci-apply (MIGRATION.md, "CI").
  tags = ["ci-skip"]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  # No doppler_writes yet: the only Doppler secrets terraform-record built
  # from these clients (SURE_ and ACTUAL_POCKETID_CLIENT) are let go, not
  # moved, since their client secrets can't be read back. Phase 3 adds
  # k8s-at-home/min here when it rotates the clients and owns them again.
  providers = ["pocketid"]
}
