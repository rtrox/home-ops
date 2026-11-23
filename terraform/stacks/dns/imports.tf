# Migration phase 2 (P2-2): what this stack adopts from terraform-record's
# cloudflare stack, which forgets it (removed, destroy = false) before this
# stack is applied. See MIGRATION.md. Delete this file and import-ids.jq in
# the cleanup PR once the zero-diff gate passes.
#
# Each import iterates over this stack's own config (local.zones,
# local.dns_records), so every configured object must have an ID below: a
# missing one fails the plan instead of planning a create.
#
# Not moving: terraform-record's namedotcom_domain_nameservers. It forgets
# them and nothing manages them (the domains are moving to Cloudflare
# Registrar by hand).

import {
  for_each = local.zones
  to       = module.zone[each.key].cloudflare_zone.this
  id       = local.imported_zone_ids[each.key]
}

import {
  for_each = local.zones
  to       = module.zone[each.key].cloudflare_ruleset.waf_custom_rules
  id       = "zones/${local.imported_zone_ids[each.key]}/${local.imported_ruleset_ids[each.key]}"
}

import {
  for_each = local.dns_records
  to       = cloudflare_dns_record.this[each.key]
  id       = "${local.imported_zone_ids[each.value.zone]}/${local.imported_record_ids[each.key]}"
}

# Cloudflare IDs (not secrets), from terraform-record cloudflare's state.
# PLACEHOLDERS ("PENDING" fails the import, so nothing is planned until the
# real IDs are in): replace this whole block with MIGRATION.md step 1's output.
locals {
  imported_zone_ids = {
    "lyb.app"             = "PENDING"
    "missprissquilts.com" = "PENDING"
    "rtrox.co"            = "PENDING"
    "rtrox.com"           = "PENDING"
    "rtrox.dev"           = "PENDING"
    "rtrox.io"            = "PENDING"
    "troxel.io"           = "PENDING"
    "trxl.ink"            = "PENDING"
    "trxl.io"             = "PENDING"
    "trxl.tech"           = "PENDING"
  }
  imported_ruleset_ids = {
    "lyb.app"             = "PENDING"
    "missprissquilts.com" = "PENDING"
    "rtrox.co"            = "PENDING"
    "rtrox.com"           = "PENDING"
    "rtrox.dev"           = "PENDING"
    "rtrox.io"            = "PENDING"
    "troxel.io"           = "PENDING"
    "trxl.ink"            = "PENDING"
    "trxl.io"             = "PENDING"
    "trxl.tech"           = "PENDING"
  }
  imported_record_ids = {
    "rtrox.com/dmarc_reject"             = "PENDING"
    "rtrox.com/null_mx"                  = "PENDING"
    "rtrox.com/spf_none"                 = "PENDING"
    "rtrox.dev/simplelogin_dkim"         = "PENDING"
    "rtrox.dev/simplelogin_dkim_2"       = "PENDING"
    "rtrox.dev/simplelogin_dkim_3"       = "PENDING"
    "rtrox.dev/simplelogin_dmarc"        = "PENDING"
    "rtrox.dev/simplelogin_mx_10"        = "PENDING"
    "rtrox.dev/simplelogin_mx_20"        = "PENDING"
    "rtrox.dev/simplelogin_spf"          = "PENDING"
    "rtrox.dev/simplelogin_verification" = "PENDING"
    "rtrox.io/bluesky_atproto"           = "PENDING"
    "rtrox.io/bluesky_atproto_asdf2"     = "PENDING"
    "rtrox.io/protonmail_dkim"           = "PENDING"
    "rtrox.io/protonmail_dkim_2"         = "PENDING"
    "rtrox.io/protonmail_dkim_3"         = "PENDING"
    "rtrox.io/protonmail_dmarc"          = "PENDING"
    "rtrox.io/protonmail_mx_10"          = "PENDING"
    "rtrox.io/protonmail_mx_20"          = "PENDING"
    "rtrox.io/protonmail_spf"            = "PENDING"
    "rtrox.io/protonmail_verification"   = "PENDING"
    "rtrox.io/resend_dkim"               = "PENDING"
    "rtrox.io/resend_mx"                 = "PENDING"
    "rtrox.io/resend_spf"                = "PENDING"
    "troxel.io/google_dkim"              = "PENDING"
    "troxel.io/google_verification"      = "PENDING"
    "troxel.io/proton_mx_1"              = "PENDING"
    "troxel.io/proton_mx_2"              = "PENDING"
    "troxel.io/protonmail_dkim"          = "PENDING"
    "troxel.io/protonmail_dkim2"         = "PENDING"
    "troxel.io/protonmail_dkim3"         = "PENDING"
    "troxel.io/protonmail_dmarc"         = "PENDING"
    "troxel.io/protonmail_spf"           = "PENDING"
    "troxel.io/protonmail_verification"  = "PENDING"
    "troxel.io/sendgrid_dkim_s1"         = "PENDING"
    "troxel.io/sendgrid_dkim_s2"         = "PENDING"
    "troxel.io/sendgrid_link"            = "PENDING"
    "trxl.io/dmarc"                      = "PENDING"
    "trxl.io/resend_dkim"                = "PENDING"
    "trxl.io/send_mx"                    = "PENDING"
    "trxl.io/send_spf"                   = "PENDING"
    "trxl.io/sendgrid_dkim_s1"           = "PENDING"
    "trxl.io/sendgrid_dkim_s2"           = "PENDING"
    "trxl.io/sendgrid_em"                = "PENDING"
    "trxl.io/sendgrid_link"              = "PENDING"
    "trxl.io/sendgrid_link_id"           = "PENDING"
  }
}
