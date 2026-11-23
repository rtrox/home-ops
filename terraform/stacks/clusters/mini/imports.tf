# Migration P2-3: what this stack adopts from terraform-record's cloudflare and
# backblaze stacks, which forget it first (removed, destroy = false). See
# MIGRATION.md. Delete this file, and the two preconditions marked "P2-3 move
# only" (tunnel.tf, volsync.tf), in the cleanup PR once the zero-diff gate
# passes.
#
# The tokens and B2 keys aren't here: they're new (rotated), and their Doppler
# secrets are imported and updated to them.

# --- By-value imports ---------------------------------------------------------
#
# A random_* resource is imported by its value. The values are secrets, so
# they are never in this repo or in Doppler's tf-at-home configs: the owner
# exports them from k8s-at-home/min for the move's plans and applies only
# (MIGRATION.md, "By-value imports"). Without them, the import block below has
# nothing to import and the resource's precondition fails the plan, so a plan
# can't quietly create a new tunnel secret or restic password instead.

variable "import_tunnel_secret" {
  description = "P2-3 only: the live tunnel secret, CLOUDFLARED_CREDENTIALS's TunnelSecret in k8s-at-home/min (standard base64 of 35 bytes)."
  type        = string
  sensitive   = true
  default     = null

  validation {
    # 35 bytes are 48 base64 characters, the last one padding.
    condition     = var.import_tunnel_secret == null || can(regex("^[A-Za-z0-9+/]{47}=$", var.import_tunnel_secret))
    error_message = "import_tunnel_secret isn't 35 bytes of standard base64. It must be CLOUDFLARED_CREDENTIALS's TunnelSecret, unchanged."
  }
}

variable "import_restic_password" {
  description = "P2-3 only: the live restic password, VOLSYNC_BACKBLAZE_BUCKET's restic_password in k8s-at-home/min (32 letters and digits)."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.import_restic_password == null || can(regex("^[A-Za-z0-9]{32}$", var.import_restic_password))
    error_message = "import_restic_password isn't 32 letters and digits. It must be VOLSYNC_BACKBLAZE_BUCKET's restic_password, unchanged."
  }
}

# An import ID can't be sensitive, hence nonsensitive(): tofu prints it in the
# plan ("(imported from ...)", "Preparing import... [id=...]") and the apply
# ("Importing... [id=...]"). MIGRATION.md's commands redact those lines; run
# these plans and applies only through them. After the import, nothing prints
# either value (random_bytes has no id; random_password's is "none").
#
# random_bytes' import ID is the standard base64 of the bytes, which is exactly
# what TunnelSecret holds (terraform-record's random_id.b64_std).
import {
  for_each = nonsensitive(var.import_tunnel_secret != null) ? toset(["this"]) : toset([])
  to       = random_bytes.tunnel_secret
  id       = nonsensitive(var.import_tunnel_secret)
}

# random_password's import ID is the password.
import {
  for_each = nonsensitive(var.import_restic_password != null) ? toset(["this"]) : toset([])
  to       = random_password.volsync_restic
  id       = nonsensitive(var.import_restic_password)
}

# --- Imports by ID ------------------------------------------------------------

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

# The tunnel, found by name among the account's live tunnels (the lookup fails
# unless exactly one matches).
data "cloudflare_zero_trust_tunnel_cloudflared" "imported" {
  account_id = local.account_id
  filter = {
    name       = "mini_external_ingress"
    is_deleted = false
  }
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.mini
  id = "${local.account_id}/${data.cloudflare_zero_trust_tunnel_cloudflared.imported.id}"
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

# The Doppler secrets (project.config.NAME). CLOUDFLARED_CREDENTIALS imports
# unchanged; the other five update to the new token or key.
import {
  to = doppler_secret.external_dns_token
  id = "k8s-at-home.min.EXTERNALDNS_CLOUDFLARE_TOKEN"
}

import {
  to = doppler_secret.cert_manager_token
  id = "k8s-at-home.min.CERTMANAGER_CLOUDFLARE_TOKEN"
}

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
