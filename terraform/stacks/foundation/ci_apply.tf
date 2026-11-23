# CI's apply credentials: the Doppler config tf-at-home/ci-apply, which the
# `terraform-apply` workflow reads with a read-only service token kept in the
# GitHub Environment secret CI_DOPPLER_TF_APPLY (environments.tf). The config
# is its own root, so the ci and prd tokens can't read it.
#
# What goes in it (see .github/workflows/terraform-apply.yaml):
#   R2_STATE_READWRITE     here: a CI-only read/write R2 token, separate from
#                          the laptop's, so CI's state access is revoked alone
#   TOFU_STATE_PASSPHRASE  NOT here: a Doppler reference to the prd value, set
#                          by hand (MIGRATION.md, P2-1b step 1). A doppler_secret
#                          would store the resolved passphrase in this stack's
#                          state (its `computed` attribute), and Terraform must
#                          never hold it.
# Each stack's provider credentials are added when that stack opts in to
# ci-apply (none yet). DOPPLER_HOSTS_TOKEN, which the workflow also reads if
# present, is not created: no stack needs it yet.

# Same permissions as the laptop's read/write token, its own token. No
# prevent_destroy, unlike the laptop's: replacing it only cuts CI off until the
# apply finishes (the laptop's own state access doesn't depend on it), and being
# able to revoke it is the point. Created before the old one is deleted, so
# ci-apply never holds a dead key.
resource "cloudflare_api_token" "r2_state_ci_apply" {
  name   = "tofu-state-ci-apply-readwrite"
  status = "active"

  policies = [{
    effect            = "allow"
    permission_groups = [for name in local.r2_state_tokens.readwrite : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ (local.r2_bucket_resource) = "*" })
  }]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.r2_state_tokens.readwrite : local.permission_group_ids[name] != null])
      error_message = "An R2 permission group was not found by name; Cloudflare may have renamed it."
    }
  }
}

# Same shape and key name as the laptop's (and ci's R2_STATE_READONLY), so
# tf-ci.sh reads it with `.R2_STATE_READWRITE`.
resource "doppler_secret" "ci_apply_r2_state" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = "R2_STATE_READWRITE"
  value = jsonencode({
    access_key_id     = cloudflare_api_token.r2_state_ci_apply.id
    secret_access_key = sha256(cloudflare_api_token.r2_state_ci_apply.value)
    endpoint          = local.r2_endpoint
    bucket            = cloudflare_r2_bucket.tofu_state.name
  })
}

# The token the apply jobs read this config with. Read-only: the jobs' own
# writes to Doppler go through per-config write tokens, added to ci-apply as
# stacks opt in.
resource "doppler_service_token" "ci_apply_read" {
  project = doppler_config.this["tf-at-home/ci-apply"].project
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = "ci-apply-read"
  access  = "read"

  lifecycle {
    # Every argument forces a new token; the Environment secrets pick the new
    # one up in the same apply, once it exists.
    create_before_destroy = true
  }
}
