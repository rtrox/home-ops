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
  # access). Narrowing them to what Cloud Sync needs is a follow-up.
  keys = {
    "nas-rtrox-io-truenas-backup" = {}
  }
}

resource "doppler_secret" "nas_backup_bucket" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "TRUENAS_BACKUP_BUCKET"
  value = jsonencode({
    application_key_id = module.nas_backup_bucket.keys["nas-rtrox-io-truenas-backup"].application_key_id
    application_key    = module.nas_backup_bucket.keys["nas-rtrox-io-truenas-backup"].application_key
    endpoint           = module.nas_backup_bucket.bucket.endpoint
    bucket             = module.nas_backup_bucket.bucket.name
  })
}
