# A Cloudflare token for the clusters/mini stack (terraform/stacks/clusters/mini),
# read through `provider_keys` like the dns stack's (dns_token.tf).
#
# What that stack manages: mini.rtrox.io's A records (DNS Write, and Zone Read
# for the zone lookup), mini's Cloudflare Tunnel (an account-level permission:
# Cloudflare can't limit a token to one tunnel) and the external-dns and
# cert-manager tokens (API Tokens Write, user-level).
#
# API Tokens Write lets a token create tokens with any permission the owner's
# user has, so this token can reach as far as CLOUDFLARE_TERRAFORM_TOKEN. Keep
# that in mind before clusters/mini is applied from CI (`ci-apply`): its
# ci-apply copy would hand that reach to every apply job.
locals {
  mini_token_permissions = {
    zone    = ["Zone Read", "DNS Write"]
    account = ["Cloudflare Tunnel Write"]
    user    = ["API Tokens Write"]
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
    {
      effect            = "allow"
      permission_groups = [for name in local.mini_token_permissions.user : { id = local.permission_group_ids[name] }]
      # A string, not jsonencode(): a sensitive value can't be a map key.
      resources = "{\"com.cloudflare.api.user.${local.cloudflare_user_id}\":\"*\"}"
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
      # Never issue a user-scoped policy without a user in it.
      condition     = can(regex("^[0-9a-f]{32}$", local.cloudflare_user_id))
      error_message = "tf-at-home/prd CLOUDFLARE_USER_ID is missing or isn't a 32-character hex Cloudflare user ID (MIGRATION.md step 0)."
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

# The clusters/mini stack reads this key (provider_keys in its stack.tm.hcl):
# the laptop from prd; ci-apply is there for when the stack opts in.
resource "doppler_secret" "mini_token_prd" {
  project = "tf-at-home"
  config  = "prd"
  name    = "CLOUDFLARE_MINI_TOKEN"
  value   = cloudflare_api_token.mini.value
}

resource "doppler_secret" "mini_token_ci_apply" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = "CLOUDFLARE_MINI_TOKEN"
  value   = cloudflare_api_token.mini.value
}

# CI's plans and drift runs read the same key name from ci, holding the
# read-only token. It can't plan clusters/mini yet: it has no tunnel
# permission, and ci has no B2 key or k8s-at-home/min token (see
# terraform/stacks/clusters/mini/MIGRATION.md, "CI").
resource "doppler_secret" "mini_token_ci" {
  project = "tf-at-home"
  config  = "ci"
  name    = "CLOUDFLARE_MINI_TOKEN"
  value   = cloudflare_api_token.ci_readonly.value
}
