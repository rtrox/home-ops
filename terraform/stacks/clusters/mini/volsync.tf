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

# Read by every app's ${APP}-volsync-b2 ExternalSecret (components/volsync).
# The restic password isn't here: it's VOLSYNC_B2_RESTIC_PASSWORD, made by
# hand in k8s-at-home/min and never in Terraform (migration P2-3), so no
# apply can change the password every B2 repository is encrypted with.
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
  })
}
