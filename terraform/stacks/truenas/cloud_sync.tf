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
# The credential is never compared with TrueNAS, only replaced when the key
# changes. CI plans read TrueNAS with a read-only API key, which gets secret
# fields back as a placeholder, so comparing them would show a change on every
# CI plan. Once the replace trigger below lands, a new B2 key (a rotation, or a
# replace under the same name) has a new key ID, hence a new credential, named
# after that ID so names never clash: created first, the task moved to it, then
# the old one deleted. The plan shows a replace, so a ci-apply run waits for
# approval.
resource "terraform_data" "nas_backup_key" {
  input = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key_id
}

resource "truenas_cloudsync_credential" "nas_backup" {
  name          = "nas-backup-${module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key_id}"
  provider_type = "B2"
  provider_attributes_json = jsonencode({
    account = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key_id
    key     = module.nas_backup_locked_bucket.keys[local.nas_backup_key].application_key
  })

  # replace_triggered_by = [terraform_data.nas_backup_key] comes in the next
  # change: added in the same apply as terraform_data, that resource's create
  # would itself trigger a replace. **Don't rotate the key until it lands**:
  # the apply would rename this credential but keep the old secret (Update
  # resends the state's), and removing the old key would then stop backups.
  lifecycle {
    ignore_changes        = [provider_attributes_json]
    create_before_destroy = true
  }
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

  enabled = true

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
