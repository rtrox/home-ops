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
locals {
  imported_zone_ids = {
    "lyb.app"             = "bc6eec9dcf8f851d8c4ca094d0add851"
    "missprissquilts.com" = "007715bac65b994f30b702286e8c8bf7"
    "rtrox.co"            = "48c3509409d9db7e6bde5198205052cd"
    "rtrox.com"           = "55bd84dc805f13b4ffeec347d7a35839"
    "rtrox.dev"           = "07ce72253342086d208bbc5ce0e8d492"
    "rtrox.io"            = "9aedc7db6baa3b7dffd1e1ef54f7b7d2"
    "troxel.io"           = "7a5ab04ebe23ba95b887dfffd6717fc8"
    "trxl.ink"            = "b8d6e72f56a21601c879407e70ff22a9"
    "trxl.io"             = "b315f1eeb11e41eed005a0484f00f3bf"
    "trxl.tech"           = "5acca915af5dfb495520e9c92e46dadb"
  }
  imported_ruleset_ids = {
    "lyb.app"             = "15af3610fe084a899a99eee1f5ca971f"
    "missprissquilts.com" = "60487871134447ec90f683858b65e042"
    "rtrox.co"            = "24c7ce36dce04843a34c763f5d1d5e6a"
    "rtrox.com"           = "87c1f1dab25a402da9bede6711f42979"
    "rtrox.dev"           = "f4f64dd236bf4606a8dae3db620a0d58"
    "rtrox.io"            = "41cb43e488384839a178a9469ac0e3b3"
    "troxel.io"           = "bc7f95f7f1a04bca8071d25c4c492c18"
    "trxl.ink"            = "af3fce1212dc4d4196f99cec8ad04ad8"
    "trxl.io"             = "c08e24fd6dbf4bcfb90d53d316e716d5"
    "trxl.tech"           = "27aa78977454404db85b2863628dc55f"
  }
  imported_record_ids = {
    "rtrox.com/dmarc_reject"             = "1e820e3cb2b31d63aa00d4678b386952"
    "rtrox.com/null_mx"                  = "7385f4e747e899010dc79a88268938a0"
    "rtrox.com/spf_none"                 = "6c2fdccf21e6953ea860d977965df35f"
    "rtrox.dev/simplelogin_dkim"         = "0ddeddd6afe23dca8578b50dcb634d7e"
    "rtrox.dev/simplelogin_dkim_2"       = "11e61f9f887edaeb2901f84d8ce3ac78"
    "rtrox.dev/simplelogin_dkim_3"       = "e9a7c8d362c2920732c378abd19835df"
    "rtrox.dev/simplelogin_dmarc"        = "50e5045a9fb83e676d6bed999909d2c4"
    "rtrox.dev/simplelogin_mx_10"        = "f00f766490e1d1a60c25fcae6d10b1e4"
    "rtrox.dev/simplelogin_mx_20"        = "b0074b0b3cf3da303fa24f3b1d687e3d"
    "rtrox.dev/simplelogin_spf"          = "6143e73199ee04ddbc6f7c019aa3be4b"
    "rtrox.dev/simplelogin_verification" = "80d478552fc2acc9955af464c31795a7"
    "rtrox.io/bluesky_atproto"           = "06395c1e53e92190c99d1bd4ddd4c22a"
    "rtrox.io/bluesky_atproto_asdf2"     = "25e5661bdc47eddae7a0534e7de4b9cc"
    "rtrox.io/protonmail_dkim"           = "fbacaa69bf52cf73f78191891694e05b"
    "rtrox.io/protonmail_dkim_2"         = "4e74c83b82d6fae48835fb4fefd8ca63"
    "rtrox.io/protonmail_dkim_3"         = "696f49cb528263a78ba27a9ca012fb01"
    "rtrox.io/protonmail_dmarc"          = "7cdbc6a788af214debc24e08936eed20"
    "rtrox.io/protonmail_mx_10"          = "09703614036ef3de51f31c0402d38335"
    "rtrox.io/protonmail_mx_20"          = "29e06e1da5aecbaad1d484067498ce5c"
    "rtrox.io/protonmail_spf"            = "8c3532744152ea20421b4db0744559e8"
    "rtrox.io/protonmail_verification"   = "8e5a176c1c3341e930aab34494e5a455"
    "rtrox.io/resend_dkim"               = "ae563d2be032d336f4ef303e84df382c"
    "rtrox.io/resend_mx"                 = "941c393c79fbf78c2eafe02114d82a1c"
    "rtrox.io/resend_spf"                = "f6a8bdb596171cbeabbfd64049a4253e"
    "troxel.io/google_dkim"              = "57c7bd003237fc2e1bcdde6cf1188059"
    "troxel.io/google_verification"      = "98d87d04515fde10c0e61091116d8bba"
    "troxel.io/proton_mx_1"              = "cdd37ed7c336a64bf9d5b86c3d255288"
    "troxel.io/proton_mx_2"              = "65e500f6386556c86bcedbe46767acc9"
    "troxel.io/protonmail_dkim"          = "273b1cb51ec2c093cea9fd73dbadf3b6"
    "troxel.io/protonmail_dkim2"         = "96ba41e0698823c1df03f5ab4d3ac72d"
    "troxel.io/protonmail_dkim3"         = "fc1200a1123225b890ff688ae18c63ad"
    "troxel.io/protonmail_dmarc"         = "5c286be2e8a552792d685c18b8735773"
    "troxel.io/protonmail_spf"           = "492bcd3970111410b1603e701ecc8dfc"
    "troxel.io/protonmail_verification"  = "312eded791fe449d2e8074ed7a2d077a"
    "troxel.io/sendgrid_dkim_s1"         = "28f9a38f326efcbd9376b9f15ad0c2d9"
    "troxel.io/sendgrid_dkim_s2"         = "7343d0ea9fdca66feaa1e8809ddb6bd9"
    "troxel.io/sendgrid_link"            = "49642e628d3458c18b9e9f4693a7e580"
    "trxl.io/dmarc"                      = "9c8373241624917eac8d38d11b21e83d"
    "trxl.io/resend_dkim"                = "6b3bde05077d7e72b7a1561b03a248fd"
    "trxl.io/send_mx"                    = "a5cfa52cf92421a5bc2fcae9097f2f2a"
    "trxl.io/send_spf"                   = "fc0788777ce30b0392019cfcfea919ed"
    "trxl.io/sendgrid_dkim_s1"           = "a615d2641d2c9d06c2bdf49d37e45c6b"
    "trxl.io/sendgrid_dkim_s2"           = "bd369e1f47cc1902706813e840f3a90e"
    "trxl.io/sendgrid_em"                = "359e681cf7ac370f816a73a9940acac7"
    "trxl.io/sendgrid_link"              = "673061ae236f66be4581ae10fb532656"
    "trxl.io/sendgrid_link_id"           = "9724884c1ca9c27ef8655c737746e7ce"
  }
}
