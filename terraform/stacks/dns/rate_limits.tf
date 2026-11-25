# The short domains' rate limit (curt): their links are public. trx.fm and
# app.trx.fm share trx.fm's rule. The Free plan allows one rule per zone,
# matching on the path, counting per IP over 10 seconds and blocking for 10.
# cf.colo.id is required: counts are per Cloudflare data center.
resource "cloudflare_ruleset" "short_link_rate_limit" {
  for_each = local.short_link_zones

  zone_id = module.zone[each.key].zone_id
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

moved {
  from = cloudflare_ruleset.trx_fm_rate_limit
  to   = cloudflare_ruleset.short_link_rate_limit["trx.fm"]
}
