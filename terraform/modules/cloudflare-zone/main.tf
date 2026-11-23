# One Cloudflare zone and its custom WAF ruleset. Records are not here:
# zone-level records are the calling stack's, and a host's or cluster's own
# records live in that host's or cluster's stack, which finds the zone with a
# cloudflare_zone data source.
#
# The registrar's nameservers aren't managed by Terraform: the domains are
# moving to Cloudflare Registrar (by hand), after which Cloudflare keeps the
# delegation itself.
resource "cloudflare_zone" "this" {
  name = var.domain
  account = {
    id = var.account_id
  }
  type = "full"

  lifecycle {
    # Deleting a zone deletes every record in it, including the ones other
    # stacks and external-dns manage, and a recreated zone gets new
    # nameservers.
    prevent_destroy = true
  }
}

resource "cloudflare_ruleset" "waf_custom_rules" {
  zone_id = cloudflare_zone.this.id
  name    = "Zone custom WAF ruleset"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    for rule in var.waf_custom_rules : {
      enabled     = rule.enabled
      description = rule.description
      expression  = rule.expression
      action      = rule.action
      action_parameters = rule.skip_ruleset != null ? {
        ruleset = rule.skip_ruleset
      } : null
    }
  ]
}
