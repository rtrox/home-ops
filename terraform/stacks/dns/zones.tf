# The account, found through one of its zones (as the proxmox stack finds
# rtrox.io). CI's read-only token has Zone Read but no account permission: the
# one that lists accounts (Account Settings Read) also reads account members
# and audit logs, so it isn't granted. All the zones are in this account.
data "cloudflare_zone" "rtrox_io" {
  filter = {
    name = "rtrox.io"
  }
}

locals {
  account_id = data.cloudflare_zone.rtrox_io.account.id

  # Every zone gets these, last.
  waf_default_rules = [
    {
      description = "Firewall rule to block bots and threats determined by CF"
      expression  = "(cf.client.bot) or (cf.threat_score gt 14)"
      action      = "block"
    },
    {
      description = "Firewall rule to block certain countries"
      expression  = "(ip.geoip.country in {\"CN\" \"IN\" \"KP\" \"RU\"})"
      action      = "block"
    },
  ]

  # Zone -> its own WAF rules, which come before the defaults, and whether
  # DNSSEC is managed (and on) for it.
  zones = {
    "missprissquilts.com" = { waf_rules = [], dnssec = true }
    "qol.ink"             = { waf_rules = [], dnssec = true }
    "rmt.dev"             = { waf_rules = [], dnssec = true }
    "rtrox.co"            = { waf_rules = [], dnssec = true }
    "rtrox.com"           = { waf_rules = [], dnssec = true }
    "rtrox.dev"           = { waf_rules = [], dnssec = true }
    "rtrox.io" = {
      # Unsigned on purpose: split DNS (an internal Knot zone overrides it).
      dnssec = false
      waf_rules = [
        {
          description  = "Skip bot/threat blocking for Flux GitHub webhook receivers"
          expression   = "(http.host contains \"flux-\") and (http.request.uri.path contains \"/hook/\")"
          action       = "skip"
          skip_ruleset = "current"
        },
      ]
    }
    "rvl.ink"   = { waf_rules = [], dnssec = true }
    "sxl.ink"   = { waf_rules = [], dnssec = true }
    "troxel.io" = { waf_rules = [], dnssec = true }
    "trxl.ink"  = { waf_rules = [], dnssec = true }
    "trxl.io"   = { waf_rules = [], dnssec = true }
    "trxl.tech" = { waf_rules = [], dnssec = true }
  }
}

module "zone" {
  source   = "../../modules/cloudflare-zone"
  for_each = local.zones

  account_id       = local.account_id
  domain           = each.key
  waf_custom_rules = concat(each.value.waf_rules, local.waf_default_rules)
}

# DNSSEC for every zone except rtrox.io. Destroying this resource disables
# DNSSEC (the provider sets status disabled, then deletes the settings), which
# can break resolution while the DS record is removed, hence prevent_destroy.
# The registrar (Cloudflare Registrar) publishes the DS record itself.
# To turn DNSSEC off for a zone, set status = "disabled" and apply (Cloudflare
# pulls the DS first); never just delete the entry. Until the registry has a
# new zone's DS, Cloudflare reports status "pending", so plans show
# pending -> active for it: harmless, and gone once the DS is published.
resource "cloudflare_zone_dnssec" "this" {
  for_each = { for name, z in local.zones : name => z if z.dnssec }

  zone_id = module.zone[each.key].zone_id
  status  = "active"

  lifecycle {
    prevent_destroy = true
  }
}
