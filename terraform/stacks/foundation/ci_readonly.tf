# Read-only credentials for home-ops' PR plan jobs (the self-hosted runner).
# They live in their own Doppler root config, tf-at-home/ci, which CI's service
# token reads; tf-at-home/prd (write tokens, R2 read-write, the stacks'
# Cloudflare token) is out of its reach.
# The owner's Cloudflare user (the provider token's owner), looked up rather
# than committed to this public repo. Needs "User Details Read" on the
# token's user policy.
data "cloudflare_user" "owner" {}

locals {
  # For the user-scoped "API Tokens Read" (plans refresh API tokens, e.g. the
  # proxmox stack's ACME token).
  cloudflare_user_resource = "com.cloudflare.api.user.${data.cloudflare_user.owner.id}"

  # Only what home-ops' stacks plan in CI today (proxmox: zone lookup, DNS
  # records, API tokens). Add groups when a stack needs them; never an
  # account-wide R2 read, which would expose every bucket's objects.
  ci_readonly_permissions = {
    zone = ["Zone Read", "DNS Read"]
    user = ["API Tokens Read"]
  }
}

# Reissued every 90 days; each token expires 180 days after issue.
resource "time_rotating" "ci_readonly_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "ci_readonly" {
  name       = "home-ops-ci-plan-readonly-${formatdate("YYYY-MM-DD", time_rotating.ci_readonly_token.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.ci_readonly_token.id, "4320h")

  policies = [
    {
      # Every zone in this account only (not every account the user can reach).
      effect            = "allow"
      permission_groups = [for name in local.ci_readonly_permissions.zone : { id = local.permission_group_ids[name] }]
      resources = jsonencode({
        "com.cloudflare.api.account.${local.account_id}" = { "com.cloudflare.api.account.zone.*" = "*" }
      })
    },
    {
      effect            = "allow"
      permission_groups = [for name in local.ci_readonly_permissions.user : { id = local.permission_group_ids[name] }]
      resources         = jsonencode({ (local.cloudflare_user_resource) = "*" })
    },
  ]

  lifecycle {
    # expires_on and name alone update in place and keep the old secret, so a
    # new rotation period replaces the token outright. The new token exists, and
    # Doppler has it, before the old one is deleted.
    replace_triggered_by  = [time_rotating.ci_readonly_token]
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in flatten(values(local.ci_readonly_permissions)) : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      # Never issue a user-scoped policy without a user in it.
      condition     = data.cloudflare_user.owner.id != null && data.cloudflare_user.owner.id != ""
      error_message = "The Cloudflare user lookup returned no ID."
    }
  }
}

check "ci_readonly_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.ci_readonly.expires_on, "-720h")) < 0
    error_message = "The CI read-only Cloudflare token expires within 30 days (${cloudflare_api_token.ci_readonly.expires_on}). Apply the foundation stack to reissue it, or home-ops' PR plans fail."
  }
}

# Same key names as in prd, so home-ops' generated providers and backend read
# them unchanged (they take the config name from var.doppler_config).
resource "doppler_secret" "ci_cloudflare_token" {
  project = "tf-at-home"
  config  = "ci"
  name    = "CLOUDFLARE_TERRAFORM_TOKEN"
  value   = cloudflare_api_token.ci_readonly.value
}

# The R2 state bucket's read-only credentials (r2_state.tf), copied into ci.
resource "doppler_secret" "ci_r2_state_readonly" {
  project = "tf-at-home"
  config  = "ci"
  name    = "R2_STATE_READONLY"
  value   = doppler_secret.r2_state["readonly"].value
}
