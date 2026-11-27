# One object store bucket and the application keys limited to it, on one of two
# backends (`backend`): Backblaze B2 (the default) or Garage (the NAS's S3
# store, phase 4). The outputs have the same shape for both, so a consumer
# changes backend by changing one input.
#
# Garage: the bucket's name is its global alias, and each key gets read and
# write on this bucket only (never owner). Garage has no lifecycle rules, file
# lock or capability lists, so those B2-only inputs are refused with
# backend = "garage". `endpoint` is the S3 URL consumers use; the admin API is
# configured in the calling stack's garage provider. The cluster layout stays
# out of Terraform.
#
# The module declares both providers, so every caller's lock file needs both,
# but only the backend in use is called: the other's resources have count 0.
#
# The calling stack writes each key where its consumer reads it (usually a
# doppler_secret, with `endpoint` and `bucket` alongside). Keys aren't rotated
# on a schedule: B2 keys don't expire unless asked to, and every consumer
# would need a restart. Rotate one by adding a second key and removing the
# first once its consumer has the new one.
data "b2_account_info" "current" {
  count = local.b2 ? 1 : 0
}

locals {
  b2     = var.backend == "b2"
  garage = var.backend == "garage"

  # A key with no `capabilities` gets these, ported unchanged from
  # terraform-record's bb_bucket module. Broader than most consumers need:
  # prefer listing a key's capabilities.
  default_capabilities = [
    "readFiles",
    "writeFiles",
    "deleteFiles",
    "listFiles",
    "shareFiles",
    "readBucketEncryption",
    "writeBucketEncryption",
    "readBucketReplications",
    "writeBucketReplications",
    "readBuckets",
    "listBuckets",
    "listAllBucketNames",
  ]
}

resource "b2_bucket" "this" {
  count = local.b2 ? 1 : 0

  bucket_name = var.name
  bucket_type = var.bucket_type

  dynamic "lifecycle_rules" {
    for_each = var.lifecycle_rules
    content {
      file_name_prefix                                       = lifecycle_rules.value.file_name_prefix
      days_from_uploading_to_hiding                          = lifecycle_rules.value.days_from_uploading_to_hiding
      days_from_hiding_to_deleting                           = lifecycle_rules.value.days_from_hiding_to_deleting
      days_from_starting_to_canceling_unfinished_large_files = lifecycle_rules.value.days_from_starting_to_canceling_unfinished_large_files
    }
  }

  dynamic "file_lock_configuration" {
    for_each = var.file_lock == null ? [] : [var.file_lock]
    content {
      is_file_lock_enabled = true

      dynamic "default_retention" {
        for_each = file_lock_configuration.value.default_retention == null ? [] : [file_lock_configuration.value.default_retention]
        content {
          mode = default_retention.value.mode
          period {
            duration = default_retention.value.duration
            unit     = default_retention.value.unit
          }
        }
      }
    }
  }

  lifecycle {
    # Deleting a bucket deletes its data, and a few settings (the name, turning
    # on file lock) can only change by replacing it. Never by Terraform.
    prevent_destroy = true
  }
}

resource "b2_application_key" "this" {
  for_each = local.b2 ? var.keys : {}

  key_name     = each.key
  capabilities = coalesce(each.value.capabilities, local.default_capabilities)

  # bucket_ids creates the key with B2's v4 API, and only clients that log in
  # with v4 accept it. The deprecated bucket_id creates it with an older API
  # (provider >= 0.12.1), which every client accepts.
  bucket_id  = each.value.legacy_api ? b2_bucket.this[0].bucket_id : null
  bucket_ids = each.value.legacy_api ? null : [b2_bucket.this[0].bucket_id]
}

# The B2 bucket had no count before the backend switch: keep its state.
moved {
  from = b2_bucket.this
  to   = b2_bucket.this[0]
}

resource "garage_bucket" "this" {
  count = local.garage ? 1 : 0

  global_alias = var.name

  lifecycle {
    # Deleting a bucket deletes its data. Never by Terraform.
    prevent_destroy = true
  }
}

resource "garage_key" "this" {
  for_each = local.garage ? var.keys : {}

  name = each.key
}

# Read and write on this bucket only. Never owner: that can change the
# bucket's settings and delete it.
resource "garage_bucket_key" "this" {
  for_each = local.garage ? var.keys : {}

  bucket_id     = garage_bucket.this[0].id
  access_key_id = garage_key.this[each.key].access_key_id
  read          = true
  write         = true
  owner         = false
}
