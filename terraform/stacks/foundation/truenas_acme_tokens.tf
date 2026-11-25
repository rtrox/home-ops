# The Cloudflare tokens the two TrueNAS hosts' ACME DNS-01 authenticators use,
# each limited to rtrox.io: Zone Read finds the zone, DNS Write adds and
# removes the _acme-challenge TXT record. The owner pastes each into its
# host's TrueNAS UI (Credentials > Certificates > ACME DNS-Authenticators);
# the Doppler secrets in hosts-at-home/prd are where that value is kept.
#
# Made here, not in the truenas stack, for the same reason as mini's
# controller tokens (mini_cluster_tokens.tf): no stack that may one day apply
# from CI needs a token that can create tokens. Moved from terraform-record's
# cloudflare stack in migration P2-5 (rotated: these are new tokens; the
# Doppler secrets are imported and point at them).
#
# No expiry and no scheduled reissue: the value reaches TrueNAS only by hand,
# so a reissue or an expiry would silently break the next certificate renewal.
# Rotate one by hand, rarely: `-replace` it (create before destroy), paste the
# new value into that TrueNAS, and check a DNS-01 issue works
# (terraform/stacks/truenas/README.md).
locals {
  truenas_acme_token_permissions = ["Zone Read", "DNS Write"]

  # Host (inventory/hosts.yaml) -> its token's name and the hosts-at-home/prd
  # key holding it.
  truenas_acme_tokens = {
    "nas.rtrox.io"    = { name = "nas-rtrox-io-acme-dns01", doppler_key = "TRUENAS_CLOUDFLARE_TOKEN" }
    "backup.rtrox.io" = { name = "backup-rtrox-io-acme-dns01", doppler_key = "TRUENAS_BACKUP_CLOUDFLARE_TOKEN" }
  }
}

resource "cloudflare_api_token" "truenas_acme" {
  for_each = local.truenas_acme_tokens

  name   = each.value.name
  status = "active"

  policies = [{
    effect            = "allow"
    permission_groups = [for name in local.truenas_acme_token_permissions : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.rtrox_io.zone_id}" = "*" })
  }]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.truenas_acme_token_permissions : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{32}$", data.cloudflare_zone.rtrox_io.zone_id))
      error_message = "The rtrox.io zone lookup returned no zone ID."
    }
  }
}

# hosts-at-home/prd, through the default provider (the owner's token), like
# every other Doppler write here.
resource "doppler_secret" "truenas_acme_token" {
  for_each = local.truenas_acme_tokens

  project = "hosts-at-home"
  config  = "prd"
  name    = each.value.doppler_key
  value   = cloudflare_api_token.truenas_acme[each.key].value
}
