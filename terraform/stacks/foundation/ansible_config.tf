# The Doppler config ansible/prd: passwords Terraform generates for the Ansible
# plays (written by the dns stack). The dns stack is planned and applied in CI,
# so CI needs a token for it, as for min-ci. Ansible reads the config through
# the owner's own Doppler login (task ansible:*), so no token is made for that.
#
# One token per consumer, all under the key name _provider_env.json names
# (local.doppler_write_tokens["ansible/prd"]): the laptop's read/write token is
# made in doppler.tf with the other write tokens, the other two here.
locals {
  ansible_token_key = local.doppler_write_tokens["ansible/prd"]
}

# PR plan jobs (tf-at-home/ci): read-only.
resource "doppler_service_token" "ansible_plan" {
  project = local.doppler_config_ref["ansible/prd"].project
  config  = local.doppler_config_ref["ansible/prd"].name
  name    = "ci-plan-read"
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_ansible_token" {
  project = "tf-at-home"
  config  = "ci"
  name    = local.ansible_token_key
  value   = doppler_service_token.ansible_plan.key
}

# Apply jobs (tf-at-home/ci-apply): read/write.
resource "doppler_service_token" "ansible_apply" {
  project = local.doppler_config_ref["ansible/prd"].project
  config  = local.doppler_config_ref["ansible/prd"].name
  name    = "ci-apply-write"
  access  = "read/write"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_apply_ansible_token" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = local.ansible_token_key
  value   = doppler_service_token.ansible_apply.key
}
