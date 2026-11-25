# trx.fm was registered with Cloudflare Registrar (Nov 25, 2026), which created
# its zone. Adopt the zone and its DNSSEC settings; its WAF ruleset and no-mail
# records are created. The zone ID is looked up by name. Delete this file once
# applied.

data "cloudflare_zone" "trx_fm" {
  filter = {
    name = "trx.fm"
  }
}

import {
  to = module.zone["trx.fm"].cloudflare_zone.this
  id = data.cloudflare_zone.trx_fm.id
}

import {
  to = cloudflare_zone_dnssec.this["trx.fm"]
  id = data.cloudflare_zone.trx_fm.id
}
