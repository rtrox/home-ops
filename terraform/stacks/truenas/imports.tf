# Migration P2-5: what this stack adopts from terraform-record's cloudflare and
# backblaze stacks, which forget it first (removed, destroy = false). See
# MIGRATION.md. Delete this file, p2-5-plan.json and MIGRATION.md in the
# cleanup PR once the zero-diff gate passes.
#
# Nothing is imported by value. The B2 key is new (rotated), and the Doppler
# secret below is imported and updated to it. The ACME tokens and their
# secrets go to foundation instead.

# The two records, from terraform-record's
# cloudflare_dns_record.rtrox_io_host["nas"] and ["backup"] (zone_rtrox_io.tf
# there, where these IDs are recorded too).
locals {
  imported_record_ids = {
    "nas.rtrox.io"    = "025cb954cc7aea236f7b06117efb2786" # nas, 172.21.1.12
    "backup.rtrox.io" = "b03352b718ee56a610fd30c2fed5d54f" # backup, 172.30.1.13
  }
}

import {
  for_each = local.imported_record_ids
  to       = cloudflare_dns_record.host[each.key]
  id       = "${local.zone_id}/${each.value}"
}

# The bucket, by the ID a lookup by name returns: a missing bucket fails the
# plan instead of being created.
data "b2_bucket" "imported" {
  bucket_name = "nas-rtrox-io-truenas-backup"
}

import {
  to = module.nas_backup_bucket.b2_bucket.this
  id = data.b2_bucket.imported.bucket_id
}

# The Doppler secret (project.config.NAME), updated by the import's apply to
# the new key.
import {
  to = doppler_secret.nas_backup_bucket
  id = "hosts-at-home.prd.TRUENAS_BACKUP_BUCKET"
}
