# The state bucket every stack keeps its state in, under its own key, on
# OpenTofu's S3 backend with use_lockfile (R2 supports the conditional writes
# the lock file needs). A nightly job (home-ops terraform/tofu-state-copy)
# copies it to a versioned B2 bucket for history.
#
# This stack keeps its own state in this bucket. That's safe under
# prevent_destroy; the break-glass R2 token covers the case where it isn't.
#
# Not managed here, on purpose: the break-glass R2 token (made by hand and kept
# outside Doppler, so it still works when Terraform or Doppler doesn't) and the
# state encryption passphrase. The nightly copy's read-only token and the
# history bucket are in backups.tf.
resource "cloudflare_r2_bucket" "tofu_state" {
  account_id = local.account_id
  name       = "tofu-state"
  location   = "wnam"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  r2_bucket_resource = "com.cloudflare.edge.r2.bucket.${local.account_id}_${cloudflare_r2_bucket.tofu_state.jurisdiction}_${cloudflare_r2_bucket.tofu_state.name}"
  r2_endpoint        = "https://${local.account_id}.r2.cloudflarestorage.com"

  # R2 S3 credentials derive from an API token: the access key ID is the
  # token's ID, the secret access key is the SHA-256 of its value.
  #
  # Keys are the Doppler names (R2_STATE_<KEY>), which consumers read; token
  # names say who uses them. readonly: CI's PR plans (copied into
  # tf-at-home/ci, ci_readonly.tf). readwrite: the laptop's task tf:*. CI's
  # apply jobs get their own token, in tf-at-home/ci-apply.
  r2_state_tokens = {
    readonly  = ["Workers R2 Storage Bucket Item Read"]
    readwrite = ["Workers R2 Storage Bucket Item Read", "Workers R2 Storage Bucket Item Write"]
  }
  r2_state_token_names = {
    readonly  = "tofu-state-ci-plan-readonly"
    readwrite = "tofu-state-laptop-readwrite"
  }
}

resource "cloudflare_api_token" "r2_state" {
  for_each = local.r2_state_tokens

  name   = local.r2_state_token_names[each.key]
  status = "active"

  policies = [{
    effect            = "allow"
    permission_groups = [for name in each.value : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ (local.r2_bucket_resource) = "*" })
  }]

  lifecycle {
    # Every stack's backend, this one's included, logs in with these tokens
    # (task tf:* reads R2_STATE_READWRITE once, at the start of a run). A
    # replacement would delete the token mid-apply, and the state write and
    # lock release would then get a 403. So a plan that replaces or destroys
    # one fails here; rotate deliberately instead, logged in with the
    # break-glass key (MIGRATION.md, "Rotating the R2 tokens later").
    prevent_destroy       = true
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in each.value : local.permission_group_ids[name] != null])
      error_message = "An R2 permission group was not found by name; Cloudflare may have renamed it."
    }
  }
}

# task tf:* reads R2_STATE_READWRITE; CI reads its copy of R2_STATE_READONLY.
resource "doppler_secret" "r2_state" {
  for_each = local.r2_state_tokens

  project = "tf-at-home"
  config  = "prd"
  name    = "R2_STATE_${upper(each.key)}"
  value = jsonencode({
    access_key_id     = cloudflare_api_token.r2_state[each.key].id
    secret_access_key = sha256(cloudflare_api_token.r2_state[each.key].value)
    endpoint          = local.r2_endpoint
    bucket            = cloudflare_r2_bucket.tofu_state.name
  })
}
