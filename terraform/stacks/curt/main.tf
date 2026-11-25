# curt's storage. Wrangler, in curt's own repo, deploys the Workers that use it
# and runs the D1 migrations, and never creates storage. Domains, DNS and rules
# come in a later change, once the Workers exist.

# The account, found through a zone, as the dns stack does.
data "cloudflare_zone" "trx_fm" {
  filter = {
    name = "trx.fm"
  }
}

locals {
  account_id = data.cloudflare_zone.trx_fm.account.id
}

# The links and clicks: the source of truth.
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

# For curt's Wrangler configuration (not secret).
output "d1_database_id" {
  value = cloudflare_d1_database.curt.id
}

output "kv_namespace_id" {
  value = cloudflare_workers_kv_namespace.links.id
}
