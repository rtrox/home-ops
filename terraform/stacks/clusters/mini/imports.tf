# Migration P2-3: what this stack adopts from terraform-record's cloudflare and
# backblaze stacks, which forget it first (removed, destroy = false). See
# MIGRATION.md. Delete this file, p2-3-plan.json and MIGRATION.md in the
# cleanup PR once the zero-diff gate passes.
#
# Nothing is imported by value. The tunnel and its secret are new (tunnel.tf),
# the B2 keys are new (rotated), the restic password left Terraform, and the
# Doppler secrets below are imported and updated to the new tunnel and keys.

# mini.rtrox.io's records, from terraform-record's
# cloudflare_dns_record.rtrox_io_host["mini_0".."mini_2"] (zone_rtrox_io.tf
# there, where these IDs are recorded too).
locals {
  imported_api_record_ids = {
    "node01.mini.rtrox.io" = "69c18c20a4903730127a9bd0f7cd98de" # mini_0, 172.21.31.1
    "node02.mini.rtrox.io" = "38be32eafc061dff5b813dbe1098b4fa" # mini_1, 172.21.31.2
    "node03.mini.rtrox.io" = "e0234791d5df041ff61c17fa8ef414e3" # mini_2, 172.21.31.3
  }
}

import {
  for_each = local.imported_api_record_ids
  to       = cloudflare_dns_record.api[each.key]
  id       = "${local.zone_id}/${each.value}"
}

# The buckets, by the ID a lookup by name returns: a missing bucket fails the
# plan instead of being created.
locals {
  imported_buckets = {
    volsync_store      = "k8s-rtrox-io-volsync-store"
    cnpg_offsite_store = "k8s-mini-rtrox-io-cnpg-offsite"
  }
}

data "b2_bucket" "imported" {
  for_each    = local.imported_buckets
  bucket_name = each.value
}

import {
  to = module.volsync_store.b2_bucket.this
  id = data.b2_bucket.imported["volsync_store"].bucket_id
}

import {
  to = module.cnpg_offsite_store.b2_bucket.this
  id = data.b2_bucket.imported["cnpg_offsite_store"].bucket_id
}

# The Doppler secrets (project.config.NAME), each updated by the import's
# apply: CLOUDFLARED_CREDENTIALS to the new tunnel, the others to the new keys
# (and VOLSYNC_BACKBLAZE_BUCKET without restic_password).
import {
  to = doppler_secret.cloudflared_credentials
  id = "k8s-at-home.min.CLOUDFLARED_CREDENTIALS"
}

import {
  to = doppler_secret.volsync_bucket
  id = "k8s-at-home.min.VOLSYNC_BACKBLAZE_BUCKET"
}

import {
  to = doppler_secret.cnpg_offsite_bucket
  id = "k8s-at-home.min.CNPG_OFFSITE_BACKBLAZE_BUCKET"
}

import {
  to = doppler_secret.cnpg_offsite_restore_bucket
  id = "k8s-at-home.min.CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET"
}
