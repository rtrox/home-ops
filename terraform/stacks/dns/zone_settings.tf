# Zone settings that differ from Cloudflare's defaults. The short domains serve
# curt's public links (and, on trx.fm, its dashboard): every http:// request is
# redirected to https:// before it reaches a Worker.
resource "cloudflare_zone_setting" "short_link_always_use_https" {
  for_each = local.short_link_zones

  zone_id    = module.zone[each.key].zone_id
  setting_id = "always_use_https"
  value      = "on"
}

moved {
  from = cloudflare_zone_setting.trx_fm_always_use_https
  to   = cloudflare_zone_setting.short_link_always_use_https["trx.fm"]
}
