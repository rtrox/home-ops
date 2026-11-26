# The main TrueNAS's off-site copy: a TrueNAS Cloud Sync task (rclone) pushes
# to a bucket here with the key below. Until the move to the locked bucket,
# the owner pasted that key into TrueNAS; cloud_sync.tf now writes it there.
#
# The old bucket, being retired: private, no lifecycle rules, no Object Lock.
module "nas_backup_bucket" {
  source = "../../modules/object-store"

  name = "nas-rtrox-io-truenas-backup"

  # No key: Cloud Sync writes to the locked bucket now, and the old key could
  # delete files. The next apply forgets this bucket (README.md, step 4).
  keys = {}
}

# The replacement, with Object Lock, so a leaked key can't destroy the copy
# and this stack's state can be readable by CI (phase 4, "truenas into CI").
# Filled by a server-side copy from the bucket above (README.md), then Cloud
# Sync switches to it; the old bucket goes once one run here succeeds.
#
# legacy_api: TrueNAS 25.04's rclone (1.67) logs in with B2's v1 API, which
# refuses a v4 bucket-limited key. rclone 1.73 is said to accept them.
#
# Object Lock (governance, 45 days), as the CNPG off-site bucket: neither the
# key nor the lifecycle rule can remove a version within 45 days of upload.
# Cloud Sync's deletes become hides (its rclone doesn't hard-delete), which the
# key can do without deleteFiles; the lifecycle rule removes hidden versions
# 30 days later, once they're out of the lock. A stolen key can hide files,
# but every version stays recoverable for at least 30 days.
module "nas_backup_locked_bucket" {
  source = "../../modules/object-store"

  name = "nas-rtrox-io-truenas-backup-locked"

  file_lock = {
    default_retention = {
      mode     = "governance"
      duration = 45
      unit     = "days"
    }
  }

  lifecycle_rules = [
    {
      file_name_prefix                                       = ""
      days_from_hiding_to_deleting                           = 30
      days_from_starting_to_canceling_unfinished_large_files = 7
    },
  ]

  # Cloud Sync's: list, read and write (uploads and hides), never delete or
  # bypass the lock.
  keys = {
    "nas-rtrox-io-truenas-backup-locked" = {
      capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles"]
      legacy_api   = true
    }
  }
}

locals {
  # The key in TRUENAS_BACKUP_BUCKET, the one TrueNAS should hold: the locked
  # bucket's, once this is applied.
  nas_backup_key = "nas-rtrox-io-truenas-backup-locked"
}

resource "doppler_secret" "nas_backup_bucket" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "TRUENAS_BACKUP_BUCKET"
  value = jsonencode({
    application_key_id = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key_id
    application_key    = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key
    endpoint           = module.nas_backup_locked_bucket.bucket.endpoint
    bucket             = module.nas_backup_locked_bucket.bucket.name
  })
}
