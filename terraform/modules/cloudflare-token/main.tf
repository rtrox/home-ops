# A Cloudflare API token limited to the zones it's given, reissued on a
# schedule and expiring. For consumers outside Terraform (external-dns,
# cert-manager): the calling stack writes `value` where they read it.
#
# Lifetime: a new token every var.rotation_days, each expiring
# var.lifetime_days after its issue. A token is only reissued when someone
# applies after the rotation date, so the difference is how long applies can
# lapse before the consumer's token expires; the check below warns in any plan
# within 30 days of that.
#
# A reissue creates the new token, updates whatever reads `value` (the calling
# stack's doppler_secret), then deletes the old token, all in one apply. A
# consumer that copies the secret on its own schedule (ExternalSecrets, hourly
# by default) holds a deleted token until its next sync, so expect up to an
# hour of 403s after each reissue unless the copy is refreshed by hand.
data "cloudflare_api_token_permission_groups_list" "all" {}

locals {
  # Permission group name -> ID. one() fails the plan if a name matches more
  # than one group; a name that matches none is null, which the precondition
  # below catches.
  permission_group_ids = {
    for name in var.permissions :
    name => one([for g in data.cloudflare_api_token_permission_groups_list.all.result : g.id if g.name == name])
  }
}

resource "time_rotating" "this" {
  rotation_days = var.rotation_days
}

resource "cloudflare_api_token" "this" {
  name       = "${var.name}-${formatdate("YYYY-MM-DD", time_rotating.this.id)}"
  status     = "active"
  expires_on = timeadd(time_rotating.this.id, "${var.lifetime_days * 24}h")

  policies = [{
    effect            = "allow"
    permission_groups = [for name in var.permissions : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ for zone_id in var.zone_ids : "com.cloudflare.api.account.zone.${zone_id}" => "*" })
  }]

  lifecycle {
    # expires_on and name alone update in place and keep the old secret, so a
    # new rotation period replaces the token outright, the new one first.
    replace_triggered_by  = [time_rotating.this]
    create_before_destroy = true

    precondition {
      condition     = alltrue([for name in var.permissions : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group in var.permissions was not found by name; Cloudflare may have renamed it."
    }
  }
}

check "token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.this.expires_on, "-720h")) < 0
    error_message = "The Cloudflare token ${cloudflare_api_token.this.name} expires within 30 days (${cloudflare_api_token.this.expires_on}). Apply this stack to reissue it, or its consumer loses access."
  }
}
