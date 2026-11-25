# A Cloudflare token for the truenas stack (terraform/stacks/truenas), read
# through `provider_keys` like the dns and clusters/mini stacks' tokens
# (dns_token.tf, mini_token.tf).
#
# What that stack manages: nas.rtrox.io's and backup.rtrox.io's A records
# (DNS Write, and Zone Read for the zone lookup). No API Tokens permission: the
# TrueNAS ACME tokens are made here (truenas_acme_tokens.tf), so this one can't
# mint others.
#
# Only in tf-at-home/prd for now: the stack is ci-skip and applied from the
# laptop. Its ci-apply copy (and a read-only one in ci) come with the PR that
# tags it ci-apply.
locals {
  truenas_token_permissions = ["Zone Read", "DNS Write"]
}

# Reissued every 90 days; each token expires 180 days after issue.
resource "time_rotating" "truenas_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "truenas" {
  name       = "home-ops-truenas-${formatdate("YYYY-MM-DD", time_rotating.truenas_token.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.truenas_token.id, "4320h")

  policies = [
    {
      # rtrox.io only.
      effect            = "allow"
      permission_groups = [for name in local.truenas_token_permissions : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.rtrox_io.zone_id}" = "*" })
    },
  ]

  lifecycle {
    # expires_on and name alone update in place and keep the old secret, so a
    # new rotation period replaces the token outright. The new token exists, and
    # Doppler has it, before the old one is deleted.
    replace_triggered_by  = [time_rotating.truenas_token]
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.truenas_token_permissions : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{32}$", data.cloudflare_zone.rtrox_io.zone_id))
      error_message = "The rtrox.io zone lookup returned no zone ID."
    }
  }
}

check "truenas_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.truenas.expires_on, "-720h")) < 0
    error_message = "The truenas stack's Cloudflare token expires within 30 days (${cloudflare_api_token.truenas.expires_on}). Apply the foundation stack to reissue it, or that stack's plans and applies fail."
  }
}

# The truenas stack reads this key (provider_keys in its stack.tm.hcl).
resource "doppler_secret" "truenas_token_prd" {
  project = "tf-at-home"
  config  = "prd"
  name    = "CLOUDFLARE_TRUENAS_TOKEN"
  value   = cloudflare_api_token.truenas.value
}
