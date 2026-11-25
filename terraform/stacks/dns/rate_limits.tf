# trx.fm's rate limit: its short links are public, and trx.fm and app.trx.fm
# (curt) share this one rule. The Free plan allows one rule per zone, matching
# on the path, counting per IP over 10 seconds and blocking for 10. cf.colo.id
# is required: counts are per Cloudflare data center.
resource "cloudflare_ruleset" "trx_fm_rate_limit" {
  zone_id = module.zone["trx.fm"].zone_id
  name    = "Zone rate limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      description = "Limit each address to 100 requests per 10 seconds"
      expression  = "(http.request.uri.path contains \"/\")"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 100
        mitigation_timeout  = 10
      }
    },
  ]
}
