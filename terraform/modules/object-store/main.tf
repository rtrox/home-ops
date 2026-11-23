# One object store bucket and the application keys limited to it. Backblaze B2
# only, for now: Garage stores join in phase 4.
#
# The calling stack writes each key where its consumer reads it (usually a
# doppler_secret, with `endpoint` and `bucket` alongside). Keys aren't rotated
# on a schedule: B2 keys don't expire unless asked to, and every consumer
# would need a restart. Rotate one by replacing it (`-replace`), or by adding
# a second key and removing the first once its consumer has the new one.
data "b2_account_info" "current" {}

locals {
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
  for_each = var.keys

  key_name     = each.key
  capabilities = coalesce(each.value.capabilities, local.default_capabilities)
  bucket_ids   = [b2_bucket.this.bucket_id]
}
