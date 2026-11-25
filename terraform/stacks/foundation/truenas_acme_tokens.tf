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
# The Doppler writes go through the default provider (the owner's token), not
# DOPPLER_TRUENAS_WRITE_TOKEN, as with every other Doppler write here
# (doppler.tf): deliberate, so this stack never depends on the write tokens it
# mints.
#
# No expiry and no scheduled reissue: the value reaches TrueNAS only by hand,
# so a reissue or an expiry would silently break the next certificate renewal.
#
# Rotating one, rarely, never with `-replace`: that deletes the old token in
# the same apply, before the new one is in TrueNAS. Instead:
#   1. add a second entry for the host to truenas_acme_tokens (a new key and
#      name) and point the host's `token` in truenas_acme_hosts at it; apply
#      (one token created, the Doppler secret updated);
#   2. paste the new value into that TrueNAS and prove it: a throwaway
#      staging certificate issued with the authenticator
#      (terraform/stacks/truenas/README.md);
#   3. remove the old entry; apply (the old token deleted).
locals {
  truenas_acme_token_permissions = ["Zone Read", "DNS Write"]

  # Token key -> its name. More than one per host only mid-rotation.
  truenas_acme_tokens = {
    "nas.rtrox.io"    = { name = "nas-rtrox-io-acme-dns01" }
    "backup.rtrox.io" = { name = "backup-rtrox-io-acme-dns01" }
  }

  # Host (inventory/hosts.yaml) -> the hosts-at-home/prd key holding its
  # token, and which token (a key above) that is.
  truenas_acme_hosts = {
    "nas.rtrox.io"    = { doppler_key = "TRUENAS_CLOUDFLARE_TOKEN", token = "nas.rtrox.io" }
    "backup.rtrox.io" = { doppler_key = "TRUENAS_BACKUP_CLOUDFLARE_TOKEN", token = "backup.rtrox.io" }
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
    # Only for a replacement Terraform forces; rotate as above, not by -replace.
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

resource "doppler_secret" "truenas_acme_token" {
  for_each = local.truenas_acme_hosts

  project = "hosts-at-home"
  config  = "prd"
  name    = each.value.doppler_key
  value   = cloudflare_api_token.truenas_acme[each.value.token].value
}
