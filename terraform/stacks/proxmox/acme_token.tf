# Cloudflare API token for the ACME DNS-01 plugin (acme.tf), scoped to the
# rtrox.io zone only. acme.sh's dns_cf, given just CF_Token, looks the zone up
# (Zone Read) and then writes the _acme-challenge TXT record (DNS Write).
#
# Lifetime: Terraform reissues the token every 90 days and each token expires
# 90 days after its reissue was due, so 180 days at most.
# - The token is only reissued when someone applies after the rotation date, so
#   the 90 days of slack is how long applies can lapse before renewals break.
#   Proxmox uses the token roughly every 60 days (Let's Encrypt certificates
#   last 90 days, renewed 30 days out), so the slack covers more than a full
#   renewal cycle, and an expired token costs one failed renewal attempt with
#   about a month of certificate still left to fix it.
# - 90 days bounds how long a copy that leaks (it sits in the host's
#   /etc/pve/priv/acme/plugins.cfg and in this stack's encrypted state) stays
#   useful, without reissuing on nearly every apply.
# The check below warns in any plan once the live token is within 30 days of
# expiry.
locals {
  pve_acme_token_permissions = ["Zone Read", "DNS Write"]

  # Permission group IDs by name; one() fails the plan if a name ever matches
  # more than one group, and a missing name trips the precondition below.
  pve_acme_permission_group_ids = {
    for name in local.pve_acme_token_permissions :
    name => one([for g in data.cloudflare_api_token_permission_groups_list.all.result : g.id if g.name == name])
  }
}

data "cloudflare_zone" "rtrox_io" {
  filter = {
    name = "rtrox.io"
  }
}

data "cloudflare_api_token_permission_groups_list" "all" {}

resource "time_rotating" "pve_acme_token" {
  rotation_days = 90
}

resource "cloudflare_api_token" "pve_acme" {
  name       = "pve-acme-dns01-${formatdate("YYYY-MM-DD", time_rotating.pve_acme_token.rfc3339)}"
  status     = "active"
  expires_on = timeadd(time_rotating.pve_acme_token.rotation_rfc3339, "2160h") # rotation + 90 days

  policies = [{
    effect            = "allow"
    permission_groups = [for name in local.pve_acme_token_permissions : { id = local.pve_acme_permission_group_ids[name] }]
    resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.rtrox_io.zone_id}" = "*" })
  }]

  lifecycle {
    # expires_on alone updates in place and keeps the old secret, so a new
    # rotation period replaces the token outright. The new token exists, and
    # the plugin has it, before the old one is deleted.
    replace_triggered_by  = [time_rotating.pve_acme_token]
    create_before_destroy = true

    precondition {
      condition     = alltrue([for id in values(local.pve_acme_permission_group_ids) : id != null])
      error_message = "A Cloudflare permission group in local.pve_acme_token_permissions was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      # Never issue a token that isn't pinned to a zone.
      condition     = data.cloudflare_zone.rtrox_io.zone_id != null && data.cloudflare_zone.rtrox_io.zone_id != ""
      error_message = "The rtrox.io zone lookup returned no zone ID."
    }
  }
}

check "pve_acme_token_expiry" {
  assert {
    condition     = timecmp(plantimestamp(), timeadd(cloudflare_api_token.pve_acme.expires_on, "-720h")) < 0
    error_message = "The Proxmox ACME Cloudflare token expires within 30 days (${cloudflare_api_token.pve_acme.expires_on}). Apply this stack to reissue it, or the next certificate renewal fails."
  }
}
