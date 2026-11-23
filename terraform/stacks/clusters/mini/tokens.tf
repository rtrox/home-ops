# The Cloudflare tokens mini's controllers use, each limited to rtrox.io:
# external-dns (records for HTTPRoutes and Services) and cert-manager (DNS-01
# challenge TXT records). Zone Read finds the zone, DNS Write edits records.
#
# Reissued every 90 days and expiring 180 days after issue (the
# cloudflare-token module). After a reissue, Doppler has the new token at
# once, but each ExternalSecret copies it on its next hourly refresh, and the
# old token is already gone by then: external-dns retries its sync (it doesn't
# delete records it can't read), and a certificate renewal in that hour retries
# with backoff. MIGRATION.md has the force-sync command that closes the gap.
locals {
  dns_token_permissions = ["Zone Read", "DNS Write"]
}

module "external_dns_token" {
  source = "../../../modules/cloudflare-token"

  name        = "k8s-mini-rtrox-io-external-dns"
  permissions = local.dns_token_permissions
  zone_ids    = [local.zone_id]
}

# Read by cluster-apps/base/external-dns (ExternalSecret externaldns-cloudflare-token).
resource "doppler_secret" "external_dns_token" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "EXTERNALDNS_CLOUDFLARE_TOKEN"
  value   = module.external_dns_token.value
}

module "cert_manager_token" {
  source = "../../../modules/cloudflare-token"

  name        = "k8s-mini-rtrox-io-certmanager"
  permissions = local.dns_token_permissions
  zone_ids    = [local.zone_id]
}

# Read by cluster-apps/base/cert-manager/issuers (ExternalSecret
# cloudflare-token-secret), at each DNS-01 challenge.
resource "doppler_secret" "cert_manager_token" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "CERTMANAGER_CLOUDFLARE_TOKEN"
  value   = module.cert_manager_token.value
}
