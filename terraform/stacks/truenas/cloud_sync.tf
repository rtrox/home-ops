# The main TrueNAS's off-site copy: Cloud Sync task 1 ("Backblaze Backup"),
# pushing /mnt/rusty's homes, shared and documents (its `include` list:
# /homes/**, /shared/**, /documents/**; about 0.5 TB, not media or nvr) to the
# B2 bucket in backup_bucket.tf, with its credential.
#
# The task was made by hand and is imported, never created here: the provider
# can't set Cloud Sync encryption or the include list, and the task encrypts
# (content and file names). Its updates send only the fields below, so TrueNAS
# keeps the encryption, its password and salt, the include list, and every
# other setting. Keeping them out
# of Terraform is deliberate: whoever reads this state gets the B2 key but only
# ciphertext. The password and salt are in Bitwarden.
#
# Never let Terraform replace the task: a new one would be unencrypted and
# have no include list, so it would push all 57 TB of /mnt/rusty in plain
# text and hide the encrypted copies. Hence prevent_destroy. After a disaster,
# recreate it by hand in the UI (same path, include list, folder, password and
# salt), then import it again.
#
# prevent_destroy doesn't cover a create. **If any plan shows
# truenas_cloud_sync.nas_backup "will be created", stop**: the task left
# state or was deleted in TrueNAS, and the create would be the unencrypted,
# unrestricted task above. Rename this address only with a `moved` block.
# Before this stack is ci-apply, CI must gate a create of it too.
resource "truenas_cloudsync_credential" "nas_backup" {
  name          = "nas-rtrox-io-truenas-backup-locked"
  provider_type = "B2"
  provider_attributes_json = jsonencode({
    account = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key_id
    key     = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key
  })
}

import {
  to = truenas_cloud_sync.nas_backup
  id = "1"
}

resource "truenas_cloud_sync" "nas_backup" {
  description   = "Backblaze Backup"
  path          = "/mnt/rusty"
  credentials   = tonumber(truenas_cloudsync_credential.nas_backup.id)
  direction     = "PUSH"
  transfer_mode = "SYNC"

  # Paused for the move to the locked bucket; turned back on after the Dry Run
  # (README.md).
  enabled = false

  # Replaced as a whole on update: every attribute the task has, not only the
  # bucket.
  attributes_json = jsonencode({
    bucket     = module.nas_backup_locked_bucket.bucket.name
    folder     = "/"
    fast_list  = true
    chunk_size = 96
  })

  schedule_minute = "0"
  schedule_hour   = "0"
  schedule_dom    = "*"
  schedule_month  = "*"
  schedule_dow    = "*"

  lifecycle {
    prevent_destroy = true
  }
}
