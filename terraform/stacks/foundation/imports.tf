# Migration P2-5: the TrueNAS ACME tokens' Doppler secrets in hosts-at-home/prd,
# from terraform-record's cloudflare stack, which forgets them first (removed,
# destroy = false). The tokens are new (truenas_acme_tokens.tf); the secrets
# are imported and updated to them. See terraform/stacks/truenas/MIGRATION.md.
# Delete this file and p2-5-plan*.json in the cleanup PR once the zero-diff
# gate passes.
import {
  for_each = local.truenas_acme_tokens
  to       = doppler_secret.truenas_acme_token[each.key]
  id       = "hosts-at-home.prd.${each.value.doppler_key}"
}
