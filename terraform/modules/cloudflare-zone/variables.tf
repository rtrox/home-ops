variable "account_id" {
  description = "Cloudflare account the zone belongs to."
  type        = string
}

variable "domain" {
  description = "The zone's domain name, e.g. rtrox.io."
  type        = string
}

variable "waf_custom_rules" {
  description = "The zone's custom WAF rules (phase http_request_firewall_custom), in order."
  type = list(object({
    description = string
    expression  = string
    action      = string
    enabled     = optional(bool, true)
    # For action = "skip": which ruleset to skip ("current" skips the rest of
    # this one).
    skip_ruleset = optional(string)
  }))
}
