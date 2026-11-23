# rmt.dev's zone was added in the Cloudflare dashboard (Nov 23) so the domain
# could transfer to Cloudflare Registrar. Adopt it; its WAF ruleset and the
# no-mail records are created. Delete this file in the next cleanup.
import {
  to = module.zone["rmt.dev"].cloudflare_zone.this
  id = "9b76eef9ddf73b1b3899097e7c022d70"
}
