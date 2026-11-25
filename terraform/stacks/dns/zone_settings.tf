# Zone settings that differ from Cloudflare's defaults. trx.fm serves curt's
# public short links and dashboard: every http:// request is redirected to
# https:// before it reaches a Worker.
resource "cloudflare_zone_setting" "trx_fm_always_use_https" {
  zone_id    = module.zone["trx.fm"].zone_id
  setting_id = "always_use_https"
  value      = "on"
}
