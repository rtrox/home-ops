# CI's credentials for the truenas stack (terraform/stacks/truenas, "Before
# moving this stack to CI"), the same shape as the dns stack's (dns_token.tf,
# ansible_config.tf). By hand, not here: TRUENAS_API_KEY (the full key in
# ci-apply, the read-only one in ci) and the B2 keys.

# Cloudflare: the real token for applies, the read-only CI token for plans.
resource "doppler_secret" "truenas_token_ci_apply" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = "CLOUDFLARE_TRUENAS_TOKEN"
  value   = cloudflare_api_token.truenas.value
}

resource "doppler_secret" "truenas_token_ci" {
  project = "tf-at-home"
  config  = "ci"
  name    = "CLOUDFLARE_TRUENAS_TOKEN"
  value   = cloudflare_api_token.ci_readonly.value
}

# Doppler hosts-at-home/prd, which the stack writes TRUENAS_BACKUP_BUCKET to:
# read-only for plans, read/write for applies. A known gap, accepted: that
# config holds every host's secrets (the Proxmox API token among them), so
# every PR plan job can read them. Not split into a config of its own (owner's
# call, Nov 2026).
locals {
  truenas_doppler_token_key = local.doppler_write_tokens["hosts-at-home/prd"]
}

resource "doppler_service_token" "hosts_plan" {
  project = local.doppler_config_ref["hosts-at-home/prd"].project
  config  = local.doppler_config_ref["hosts-at-home/prd"].name
  name    = "ci-plan-read"
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_hosts_token" {
  project = "tf-at-home"
  config  = "ci"
  name    = local.truenas_doppler_token_key
  value   = doppler_service_token.hosts_plan.key
}

resource "doppler_service_token" "hosts_apply" {
  project = local.doppler_config_ref["hosts-at-home/prd"].project
  config  = local.doppler_config_ref["hosts-at-home/prd"].name
  name    = "ci-apply-write"
  access  = "read/write"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_apply_hosts_token" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = local.truenas_doppler_token_key
  value   = doppler_service_token.hosts_apply.key
}
