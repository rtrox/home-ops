# Bring the zones DNSSEC settings under management (they exist for every
# zone, signed or not). Delete once applied.

import {
  to = cloudflare_zone_dnssec.this["missprissquilts.com"]
  id = module.zone["missprissquilts.com"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["rmt.dev"]
  id = module.zone["rmt.dev"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["rtrox.co"]
  id = module.zone["rtrox.co"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["rtrox.com"]
  id = module.zone["rtrox.com"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["rtrox.dev"]
  id = module.zone["rtrox.dev"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["troxel.io"]
  id = module.zone["troxel.io"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["trxl.ink"]
  id = module.zone["trxl.ink"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["trxl.io"]
  id = module.zone["trxl.io"].zone_id
}

import {
  to = cloudflare_zone_dnssec.this["trxl.tech"]
  id = module.zone["trxl.tech"].zone_id
}
