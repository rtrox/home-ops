# The main TrueNAS's off-site copy: a TrueNAS Cloud Sync task (rclone) pushes
# to this bucket with the key below, which the owner pastes into TrueNAS
# (Credentials > Backup Credentials > Cloud Credentials).
#
# Same settings as terraform-record had: private, no lifecycle rules, no
# Object Lock. B2 keeps every version of an overwritten or deleted file, as
# it did before.
module "nas_backup_bucket" {
  source = "../../modules/object-store"

  name = "nas-rtrox-io-truenas-backup"

  # The default capabilities, as before the move (a rotation, not a change of
  # access). Narrowing them to what Cloud Sync needs is a follow-up. A second
  # key here only mid-rotation (README.md).
  #
  # legacy_api: TrueNAS 25.04's rclone (1.67) logs in with B2's v1 API, which
  # refuses a v4 bucket-limited key. rclone 1.73 is said to accept them.
  keys = {
    # Unused: v4-only, refused by TrueNAS. Remove once the one below is proven.
    "nas-rtrox-io-truenas-backup"        = {}
    "nas-rtrox-io-truenas-backup-legacy" = { legacy_api = true }
  }
}

locals {
  # The key in TRUENAS_BACKUP_BUCKET, the one TrueNAS should hold.
  nas_backup_key = "nas-rtrox-io-truenas-backup-legacy"
}

resource "doppler_secret" "nas_backup_bucket" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "TRUENAS_BACKUP_BUCKET"
  value = jsonencode({
    application_key_id = module.nas_backup_bucket.keys[local.nas_backup_key].application_key_id
    application_key    = module.nas_backup_bucket.keys[local.nas_backup_key].application_key
    endpoint           = module.nas_backup_bucket.bucket.endpoint
    bucket             = module.nas_backup_bucket.bucket.name
  })
}
