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

  # Zone -> its own WAF rules, which come before the defaults.
  zones = {
    "lyb.app"             = { waf_rules = [] }
    "missprissquilts.com" = { waf_rules = [] }
    "rtrox.co"            = { waf_rules = [] }
    "rtrox.com"           = { waf_rules = [] }
    "rtrox.dev"           = { waf_rules = [] }
    "rtrox.io" = {
      waf_rules = [
        {
          description  = "Skip bot/threat blocking for Flux GitHub webhook receivers"
          expression   = "(http.host contains \"flux-\") and (http.request.uri.path contains \"/hook/\")"
          action       = "skip"
          skip_ruleset = "current"
        },
      ]
    }
    "troxel.io" = { waf_rules = [] }
    "trxl.ink"  = { waf_rules = [] }
    "trxl.io"   = { waf_rules = [] }
    "trxl.tech" = { waf_rules = [] }
  }
}

module "zone" {
  source   = "../../modules/cloudflare-zone"
  for_each = local.zones

  account_id       = local.account_id
  domain           = each.key
  waf_custom_rules = concat(each.value.waf_rules, local.waf_default_rules)
}
