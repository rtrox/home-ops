# qol.ink, rvl.ink and sxl.ink were registered with Cloudflare Registrar
# (Nov 24), which created their zones. Adopt the zones and their DNSSEC
# settings; their WAF rulesets and no-mail records are created. Zone IDs are
# looked up by name. Delete this file once applied.

data "cloudflare_zone" "qol_ink" {
  filter = {
    name = "qol.ink"
  }
}

data "cloudflare_zone" "rvl_ink" {
  filter = {
    name = "rvl.ink"
  }
}

data "cloudflare_zone" "sxl_ink" {
  filter = {
    name = "sxl.ink"
  }
}

import {
  to = module.zone["qol.ink"].cloudflare_zone.this
  id = data.cloudflare_zone.qol_ink.id
}

import {
  to = module.zone["rvl.ink"].cloudflare_zone.this
  id = data.cloudflare_zone.rvl_ink.id
}

import {
  to = module.zone["sxl.ink"].cloudflare_zone.this
  id = data.cloudflare_zone.sxl_ink.id
}

import {
  to = cloudflare_zone_dnssec.this["qol.ink"]
  id = data.cloudflare_zone.qol_ink.id
}

import {
  to = cloudflare_zone_dnssec.this["rvl.ink"]
  id = data.cloudflare_zone.rvl_ink.id
}

import {
  to = cloudflare_zone_dnssec.this["sxl.ink"]
  id = data.cloudflare_zone.sxl_ink.id
}
