# curt's storage. Wrangler, in curt's own repo, deploys the Workers that use it
# and runs the D1 migrations, and never creates storage or domains.

# The public hostnames, each with its zone and the Worker that answers it. Every
# zone here must also be in foundation's curt_zones (its token's Zone Read),
# have short_links = true in the dns stack's zones.tf, and be in curt's own
# DOMAINS setting.
locals {
  custom_domains = {
    "trx.fm"     = { zone = "trx.fm", service = "curt-redirect" }
    "app.trx.fm" = { zone = "trx.fm", service = "curt-admin" }
    "rmt.dev"    = { zone = "rmt.dev", service = "curt-redirect" }
    "trxl.ink"   = { zone = "trxl.ink", service = "curt-redirect" }
  }
}

data "cloudflare_zone" "curt" {
  for_each = toset([for d in local.custom_domains : d.zone])

  filter = {
    name = each.key
  }
}

# The account, found through a zone, as the dns stack does.
locals {
  account_id = data.cloudflare_zone.curt["trx.fm"].account.id
}

# The links: the source of truth (clicks are in Analytics Engine). Its location
# is fixed when it's created: near whoever applies this.
resource "cloudflare_d1_database" "curt" {
  account_id = local.account_id
  name       = "curt"

  # Set explicitly: the provider has sent null for it (its issue 6309).
  read_replication = {
    mode = "disabled"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The redirect Worker's copy of the links.
resource "cloudflare_workers_kv_namespace" "links" {
  account_id = local.account_id
  title      = "curt-links"

  lifecycle {
    prevent_destroy = true
  }
}

# The public hostnames. Attaching one creates its DNS record and certificate, so
# the dns stack has no record for them. The Workers must already be deployed.
resource "cloudflare_workers_custom_domain" "curt" {
  for_each = local.custom_domains

  account_id = local.account_id
  zone_id    = data.cloudflare_zone.curt[each.value.zone].zone_id
  hostname   = each.key
  service    = each.value.service
}

# For curt's Wrangler configuration (not secret).
output "d1_database_id" {
  value = cloudflare_d1_database.curt.id
}

output "kv_namespace_id" {
  value = cloudflare_workers_kv_namespace.links.id
}
