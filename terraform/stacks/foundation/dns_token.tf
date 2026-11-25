# A Cloudflare token scoped to the dns stack (terraform/stacks/dns), so the
# stack doesn't read the broad CLOUDFLARE_TERRAFORM_TOKEN. Each stack gets its
# own key through `provider_keys` (terraform/terramate.tm.hcl); a new stack
# adds a token like this one rather than widening a shared one.
#
# What the dns stack manages (terraform/modules/cloudflare-zone): cloudflare_zone,
# cloudflare_dns_record, cloudflare_ruleset (http_request_firewall_custom) and
# data "cloudflare_zone" (a lookup by name, which only Zone Read covers). One policy, on every zone in this account. No
# account-level, user-level, R2 or API-token permissions.
#
# Creating a brand-new zone may need an account-level Zone permission, which is
# deliberately not granted here: add a new zone from the laptop with a broader
# token if so.
locals {
  dns_token_permissions = ["Zone Read", "Zone Write", "DNS Write", "Zone WAF Write", "Zone Settings Write"]
}

# Reissued every 90 days; each token expires 180 days after issue.
resource "time_rotating" "dns_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "dns" {
  name       = "home-ops-dns-${formatdate("YYYY-MM-DD", time_rotating.dns_token.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.dns_token.id, "4320h")

  policies = [
    {
      # Every zone in this account only (not every account the user can reach).
      effect            = "allow"
      permission_groups = [for name in local.dns_token_permissions : { id = local.permission_group_ids[name] }]
      resources = jsonencode({
        "com.cloudflare.api.account.${local.account_id}" = { "com.cloudflare.api.account.zone.*" = "*" }
      })
    },
  ]

  lifecycle {
    # expires_on and name alone update in place and keep the old secret, so a
    # new rotation period replaces the token outright. The new token exists, and
    # Doppler has it, before the old one is deleted.
    replace_triggered_by  = [time_rotating.dns_token]
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.dns_token_permissions : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
  }
}

check "dns_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.dns.expires_on, "-720h")) < 0
    error_message = "The dns stack's Cloudflare token expires within 30 days (${cloudflare_api_token.dns.expires_on}). Apply the foundation stack to reissue it, or the dns stack's plans and applies fail."
  }
}

# The dns stack reads this key (provider_keys in its stack.tm.hcl): the laptop
# from prd, CI's applies from ci-apply.
resource "doppler_secret" "dns_token_prd" {
  project = "tf-at-home"
  config  = "prd"
  name    = "CLOUDFLARE_DNS_TOKEN"
  value   = cloudflare_api_token.dns.value
}

resource "doppler_secret" "dns_token_ci_apply" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = "CLOUDFLARE_DNS_TOKEN"
  value   = cloudflare_api_token.dns.value
}

# CI's plans and drift runs read the same key name from ci, but hold the
# read-only token's value: they never get a write token.
resource "doppler_secret" "dns_token_ci" {
  project = "tf-at-home"
  config  = "ci"
  name    = "CLOUDFLARE_DNS_TOKEN"
  value   = cloudflare_api_token.ci_readonly.value
}
