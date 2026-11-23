# The backups of the root of trust, and the credentials mini's jobs write them
# with: the history of the R2 state bucket (terraform/tofu-state-copy in
# cluster-apps) and the weekly Doppler exports (security/doppler-export). They
# live here, not in clusters/mini, so restoring Terraform's state or Doppler
# never depends on a stack whose own state is in that bucket. Moved from
# terraform-record's backblaze and cloudflare stacks in migration P2-3
# (terraform/stacks/clusters/mini/MIGRATION.md): the buckets are imported, the
# keys and the R2 token are new, and the Doppler secrets are imported and point
# at them.
#
# The Doppler secrets go to k8s-at-home/min through the default provider (the
# owner's token), like every other Doppler write here.

# Read-only source credentials for the nightly copy to B2, its own token so it
# can be revoked alone. R2 S3 credentials derive from an API token (r2_state.tf).
# No expiry and no scheduled reissue, like the state bucket's other tokens and
# mini's controller tokens (mini_cluster_tokens.tf): a reissue or an expiry
# would leave the CronJob on a dead token until its ExternalSecret refreshes,
# and nothing here applies on a schedule. It reads only encrypted state.
# Rotate it by hand (`-replace`), rarely.
locals {
  r2_state_copy_permissions = ["Workers R2 Storage Bucket Item Read"]
}

resource "cloudflare_api_token" "r2_state_copy" {
  name   = "tofu-state-copy-mini-readonly"
  status = "active"

  policies = [{
    effect            = "allow"
    permission_groups = [for name in local.r2_state_copy_permissions : { id = local.permission_group_ids[name] }]
    resources         = jsonencode({ (local.r2_bucket_resource) = "*" })
  }]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = alltrue([for name in local.r2_state_copy_permissions : local.permission_group_ids[name] != null])
      error_message = "An R2 permission group was not found by name; Cloudflare may have renamed it."
    }
  }
}

resource "doppler_secret" "tofu_state_r2_source" {
  project = "k8s-at-home"
  config  = "min"
  name    = "TOFU_STATE_R2_SOURCE"
  value = jsonencode({
    access_key_id     = cloudflare_api_token.r2_state_copy.id
    secret_access_key = sha256(cloudflare_api_token.r2_state_copy.value)
    endpoint          = local.r2_endpoint
    bucket            = cloudflare_r2_bucket.tofu_state.name
  })
}

# History for the R2 state bucket. R2 has no object versioning, so the nightly
# `rclone sync` copies the bucket here, and B2 keeps old versions: an
# overwritten or deleted state file is hidden, and the lifecycle rule removes
# hidden versions 90 days later. State files are encrypted before they reach R2.
#
# The key can list and write but not read or delete: the job only compares
# listings and uploads. Restores use the provider key.
#
# Object Lock (governance, 90 days): neither the key nor the lifecycle rule can
# remove a version within 90 days of upload, so a stolen R2 read-write token or
# a bad sync still leaves 90 days of history.
module "tofu_state_history" {
  source = "../../modules/object-store"

  name = "rtrox-tofu-state-history"

  file_lock = {
    default_retention = {
      mode     = "governance"
      duration = 90
      unit     = "days"
    }
  }

  lifecycle_rules = [
    {
      file_name_prefix                                       = ""
      days_from_hiding_to_deleting                           = 90
      days_from_starting_to_canceling_unfinished_large_files = 7
    },
  ]

  keys = {
    "k8s-mini-rtrox-io-tofu-state-copy" = { capabilities = ["listBuckets", "listFiles", "writeFiles"] }
  }
}

resource "doppler_secret" "tofu_state_history_bucket" {
  project = "k8s-at-home"
  config  = "min"
  name    = "TOFU_STATE_HISTORY_BACKBLAZE_BUCKET"
  value = jsonencode({
    application_key_id = module.tofu_state_history.keys["k8s-mini-rtrox-io-tofu-state-copy"].application_key_id
    application_key    = module.tofu_state_history.keys["k8s-mini-rtrox-io-tofu-state-copy"].application_key
    endpoint           = module.tofu_state_history.bucket.endpoint
    bucket             = module.tofu_state_history.bucket.name
  })
}

# Encrypted backups of secrets and state for mini: weekly Doppler exports under
# `doppler/`, and one-off Terraform state copies under `tfstate/`. Exports are
# dated, write-once files, so age-based expiry bounds `doppler/`: a version is
# hidden 365 days after upload and removed 30 days after that. `tfstate/` has
# no expiry rule.
#
# The key can list and write but not read: the `tfstate/` copies hold the B2
# provider key and the Doppler write tokens, which the cluster must not be able
# to read even encrypted. Restores use the provider key.
#
# Object Lock (governance, 90 days): neither the key nor the lifecycle rule can
# remove a version within 90 days of upload. The key (no deleteFiles) can still
# hide files, so a stolen key can still cause loss: each hidden version goes at
# the later of 30 days after hiding and 90 days after upload.
module "mini_secrets_backup" {
  source = "../../modules/object-store"

  name = "k8s-mini-rtrox-io-secrets-backup"

  file_lock = {
    default_retention = {
      mode     = "governance"
      duration = 90
      unit     = "days"
    }
  }

  lifecycle_rules = [
    {
      file_name_prefix                                       = "doppler/"
      days_from_uploading_to_hiding                          = 365
      days_from_hiding_to_deleting                           = 30
      days_from_starting_to_canceling_unfinished_large_files = 7
    },
  ]

  keys = {
    "k8s-mini-rtrox-io-secrets-backup" = { capabilities = ["listBuckets", "listFiles", "writeFiles"] }
  }
}

resource "doppler_secret" "mini_secrets_backup_bucket" {
  project = "k8s-at-home"
  config  = "min"
  name    = "SECRETS_BACKUP_BACKBLAZE_BUCKET"
  value = jsonencode({
    application_key_id = module.mini_secrets_backup.keys["k8s-mini-rtrox-io-secrets-backup"].application_key_id
    application_key    = module.mini_secrets_backup.keys["k8s-mini-rtrox-io-secrets-backup"].application_key
    endpoint           = module.mini_secrets_backup.bucket.endpoint
    bucket             = module.mini_secrets_backup.bucket.name
  })
}
