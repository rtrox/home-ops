# Cloudflare tokens for curt, the URL shortener on Workers (stacks/curt, and
# github.com/rtrox/curt). Cloudflare can't limit these account permissions to
# one Worker, database or namespace, so each reaches every one in the account.
#
# - stack:     the curt stack's own, like mini's (mini_token.tf): storage only,
#              and Zone Read on trx.fm for the account lookup.
# - deploy:    Wrangler in curt's GitHub Actions: Worker code and D1 migrations.
#              No KV (Wrangler only binds it by ID), DNS or zone permission:
#              Terraform attaches domains.
# - analytics: the admin Worker, read-only.
#
# The last two are copied by hand (a GitHub secret, a Worker secret), so they
# don't rotate on their own: a rotation here would break them until copied.
locals {
  curt_token_permissions = {
    stack_zone = ["Zone Read"]
    stack      = ["D1 Write", "Workers KV Storage Write"]
    deploy     = ["Workers Scripts Write", "D1 Write"]
    analytics  = ["Account Analytics Read"]
  }

  # Hand-copied token -> its Doppler key (tf-at-home/prd).
  curt_hand_tokens = {
    deploy    = "CURT_DEPLOY_CLOUDFLARE_TOKEN"
    analytics = "CURT_ANALYTICS_CLOUDFLARE_TOKEN"
  }
}

data "cloudflare_zone" "trx_fm" {
  filter = {
    name = "trx.fm"
  }
}

# Reissued every 90 days; each token expires 180 days after issue.
resource "time_rotating" "curt_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "curt" {
  name       = "home-ops-curt-${formatdate("YYYY-MM-DD", time_rotating.curt_token.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.curt_token.id, "4320h")

  policies = [
    {
      # trx.fm only.
      effect            = "allow"
      permission_groups = [for name in local.curt_token_permissions.stack_zone : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.trx_fm.zone_id}" = "*" })
    },
    {
      # This account only.
      effect            = "allow"
      permission_groups = [for name in local.curt_token_permissions.stack : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.${local.account_id}" = "*" })
    },
  ]

  lifecycle {
    # As mini's token (mini_token.tf): a new period replaces the token, and
    # Doppler has the new one before the old one is deleted.
    replace_triggered_by  = [time_rotating.curt_token]
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in flatten(values(local.curt_token_permissions)) : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{32}$", data.cloudflare_zone.trx_fm.zone_id))
      error_message = "The trx.fm zone lookup returned no zone ID."
    }
  }
}

check "curt_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.curt.expires_on, "-720h")) < 0
    error_message = "The curt stack's Cloudflare token expires within 30 days (${cloudflare_api_token.curt.expires_on}). Apply the foundation stack to reissue it, or that stack's plans and applies fail."
  }
}

# The curt stack reads this key (provider_keys in its stack.tm.hcl).
resource "doppler_secret" "curt_token_prd" {
  project = "tf-at-home"
  config  = "prd"
  name    = "CLOUDFLARE_CURT_TOKEN"
  value   = cloudflare_api_token.curt.value
}

resource "cloudflare_api_token" "curt_hand" {
  for_each = local.curt_hand_tokens

  name   = "curt-${each.key}"
  status = "active"

  policies = [
    {
      # This account only.
      effect            = "allow"
      permission_groups = [for name in local.curt_token_permissions[each.key] : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ "com.cloudflare.api.account.${local.account_id}" = "*" })
    },
  ]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.curt_token_permissions[each.key] : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
  }
}

resource "doppler_secret" "curt_hand_token" {
  for_each = local.curt_hand_tokens

  project = "tf-at-home"
  config  = "prd"
  name    = each.value
  value   = cloudflare_api_token.curt_hand[each.key].value
}
