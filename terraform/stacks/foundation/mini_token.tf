# A Cloudflare token for the clusters/mini stack (terraform/stacks/clusters/mini),
# read through `provider_keys` like the dns stack's (dns_token.tf).
#
# What that stack manages: mini.rtrox.io's A records (DNS Write, and Zone Read
# for the zone lookup) and mini's Cloudflare Tunnel (an account-level
# permission: Cloudflare can't limit a token to one tunnel). No API Tokens
# permission: the tokens mini's controllers use are made here
# (mini_cluster_tokens.tf), so this one can't mint others.
#
# Only in tf-at-home/prd for now: the stack is ci-skip and applied from the
# laptop. Its ci-apply copy (and a read-only one in ci) come with the PR that
# tags it ci-apply. Every ci-apply job downloads that whole config, so a key
# goes there only once a stack needs it.
locals {
  mini_token_permissions = {
    zone    = ["Zone Read", "DNS Write"]
    account = ["Cloudflare Tunnel Write"]
  }
}

data "cloudflare_zone" "rtrox_io" {
  filter = {
    name = "rtrox.io"
  }
}

# Reissued every 90 days; each token expires 180 days after issue.
resource "time_rotating" "mini_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "mini" {
  name       = "home-ops-clusters-mini-${formatdate("YYYY-MM-DD", time_rotating.mini_token.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.mini_token.id, "4320h")

  policies = [
    {
      # rtrox.io only.
      effect            = "allow"
      permission_groups = [for name in local.mini_token_permissions.zone : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.rtrox_io.zone_id}" = "*" })
    },
    {
      # This account only.
      effect            = "allow"
      permission_groups = [for name in local.mini_token_permissions.account : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.${local.account_id}" = "*" })
    },
  ]

  lifecycle {
    # expires_on and name alone update in place and keep the old secret, so a
    # new rotation period replaces the token outright. The new token exists, and
    # Doppler has it, before the old one is deleted.
    replace_triggered_by  = [time_rotating.mini_token]
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in flatten(values(local.mini_token_permissions)) : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{32}$", data.cloudflare_zone.rtrox_io.zone_id))
      error_message = "The rtrox.io zone lookup returned no zone ID."
    }
  }
}

check "mini_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.mini.expires_on, "-720h")) < 0
    error_message = "The clusters/mini stack's Cloudflare token expires within 30 days (${cloudflare_api_token.mini.expires_on}). Apply the foundation stack to reissue it, or that stack's plans and applies fail."
  }
}

# The clusters/mini stack reads this key (provider_keys in its stack.tm.hcl).
resource "doppler_secret" "mini_token_prd" {
  project = "tf-at-home"
  config  = "prd"
  name    = "CLOUDFLARE_MINI_TOKEN"
  value   = cloudflare_api_token.mini.value
}
