# Volsync's daily restic backups to B2 (cluster-apps/components/volsync,
# b2.yaml), one repository per app under <CLUSTER_NAME>/<app>.
module "volsync_store" {
  source = "../../../modules/object-store"

  name = "k8s-rtrox-io-volsync-store"

  # Mini's restic repositories live under mini/<app>. Everything else is
  # orphaned: Bitty's (bitty/) and Chongus's (chongus/) repositories, and an
  # older layout with no cluster prefix (object names starting with "/", last
  # written 2026-07-31). Those rules expire everything under their prefix:
  # hidden a day after upload, deleted a day later. Once they've emptied their
  # prefixes, remove those three rules.
  #
  # WARNING: a new cluster named bitty or chongus would back up to bitty/ or
  # chongus/, and these rules would silently expire its backups within two
  # days. Remove the matching rule BEFORE that cluster's first volsync run.
  # Likewise, an empty CLUSTER_NAME in Doppler would make Mini write to /<app>,
  # which the "/" rule expires: don't change CLUSTER_NAME while it exists.
  #
  # mini/ only gets delete-after-hiding: restic's prune "deletes" by hiding,
  # and without this B2 keeps every pruned chunk forever. Never give mini/ an
  # upload-to-hiding rule; it would expire live backups.
  #
  # Same rules, in the same order, as terraform-record had: B2 returns them in
  # the order they were set, and the import compares them in order.
  lifecycle_rules = [
    { file_name_prefix = "mini/", days_from_hiding_to_deleting = 30, days_from_starting_to_canceling_unfinished_large_files = 7 },
    { file_name_prefix = "bitty/", days_from_uploading_to_hiding = 1, days_from_hiding_to_deleting = 1, days_from_starting_to_canceling_unfinished_large_files = 1 },
    { file_name_prefix = "chongus/", days_from_uploading_to_hiding = 1, days_from_hiding_to_deleting = 1, days_from_starting_to_canceling_unfinished_large_files = 1 },
    { file_name_prefix = "/", days_from_uploading_to_hiding = 1, days_from_hiding_to_deleting = 1, days_from_starting_to_canceling_unfinished_large_files = 1 },
  ]

  # The default capabilities, as before the move (a rotation, not a change of
  # access). restic needs list, read, write and delete; narrowing the rest is a
  # follow-up.
  keys = {
    "k8s-mini-rtrox-io-volsync-store" = {}
  }
}

# The password every restic repository in the bucket is encrypted with. It can
# never change: a new one makes every existing backup unreadable, and restic
# can't re-key a repository it can't open. So it can't be replaced
# (prevent_destroy) or changed (ignore_changes), and it was adopted by value
# from terraform-record (imports.tf). ignore_changes also hides the import's
# own difference: an imported random_password records special = true (the
# provider can't tell from the value), and special forces a replacement.
resource "random_password" "volsync_restic" {
  length  = 32
  special = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all

    # P2-3 move only (delete with imports.tf): adopted by value, so a plan
    # without the value would create a new password instead of importing it.
    precondition {
      condition     = var.import_restic_password != null
      error_message = "TF_VAR_import_restic_password is not set. Until the cleanup PR, every plan of this stack must supply it (MIGRATION.md, \"By-value imports\"); without it the plan would make a new restic password, and every existing backup would become unreadable."
    }
  }
}

# Read by every app's ${APP}-volsync-b2 ExternalSecret (components/volsync).
resource "doppler_secret" "volsync_bucket" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "VOLSYNC_BACKBLAZE_BUCKET"
  value = jsonencode({
    application_key_id = module.volsync_store.keys["k8s-mini-rtrox-io-volsync-store"].application_key_id
    application_key    = module.volsync_store.keys["k8s-mini-rtrox-io-volsync-store"].application_key
    endpoint           = module.volsync_store.bucket.endpoint
    bucket             = module.volsync_store.bucket.name
    restic_password    = random_password.volsync_restic.result
  })
}
