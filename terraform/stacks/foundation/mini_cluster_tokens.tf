# The Cloudflare tokens mini's controllers use, each limited to rtrox.io:
# external-dns (records for HTTPRoutes, Services and the tunnel's DNSEndpoint)
# and cert-manager (DNS-01 challenge TXT records). Zone Read finds the zone,
# DNS Write edits records.
#
# Made here, not in clusters/mini, so no stack that may one day apply from CI
# needs a token that can create tokens. Moved from terraform-record's
# cloudflare stack in migration P2-3 (rotated: these are new tokens; the
# Doppler secrets are imported and point at them).
#
# No expiry and no scheduled reissue: a reissue would leave each consumer on a
# deleted token until its ExternalSecret's next refresh. Rotate one by hand,
# rarely: `-replace` it (create before destroy), then force-sync its
# ExternalSecret.
locals {
  mini_cluster_token_permissions = ["Zone Read", "DNS Write"]

  # Token -> the k8s-at-home/min key its consumer reads.
  mini_cluster_tokens = {
    # cluster-apps/base/external-dns (ExternalSecret externaldns-cloudflare-token).
    "k8s-mini-external-dns" = "EXTERNALDNS_CLOUDFLARE_TOKEN"
    # cluster-apps/base/cert-manager/issuers (ExternalSecret
    # cloudflare-token-secret), read at each DNS-01 challenge.
    "k8s-mini-cert-manager" = "CERTMANAGER_CLOUDFLARE_TOKEN"
  }
}

resource "cloudflare_api_token" "mini_cluster" {
  for_each = local.mini_cluster_tokens

  name   = each.key
  status = "active"

  policies = [{
    effect            = "allow"
    permission_groups = [for name in local.mini_cluster_token_permissions : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ "com.cloudflare.api.account.zone.${data.cloudflare_zone.rtrox_io.zone_id}" = "*" })
  }]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.mini_cluster_token_permissions : local.permission_group_ids[name] != null])
      error_message = "A Cloudflare permission group was not found by name; Cloudflare may have renamed it."
    }
    precondition {
      condition     = can(regex("^[0-9a-f]{32}$", data.cloudflare_zone.rtrox_io.zone_id))
      error_message = "The rtrox.io zone lookup returned no zone ID."
    }
  }
}

resource "doppler_secret" "mini_cluster_token" {
  for_each = local.mini_cluster_tokens

  project = "k8s-at-home"
  config  = "min"
  name    = each.value
  value   = cloudflare_api_token.mini_cluster[each.key].value
}
