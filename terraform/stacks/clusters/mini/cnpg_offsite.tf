# Off-site copy of mini's CNPG backups (source: MinIO), written by the nightly
# database/cnpg-offsite job: an `rclone sync` (with a --max-delete guard,
# without --b2-hard-delete) makes the bucket follow Barman's own retention, so
# it always keeps the newest base backup and the WAL it needs. Files pruned at
# the source are hidden, then removed by the lifecycle rule 30 days later.
#
# Object Lock (governance, 45 days): neither key nor the lifecycle rule can
# remove a version within 45 days of upload. The writer key (no deleteFiles)
# can still hide files, so a stolen key still causes loss: each hidden version
# goes at the later of 30 days after hiding and 45 days after upload.
# Everything survives at least 30 days after a compromise; the newest backups
# up to 45. In steady state Barman prunes at about 15 days and hidden files go
# 30 days later, so 45 days costs no extra storage. Watch for a falling object
# count; that alert lives with the CronJob.
module "cnpg_offsite_store" {
  source = "../../../modules/object-store"

  name = "k8s-mini-rtrox-io-cnpg-offsite"

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

  keys = {
    # The nightly job's: list, read and write, never delete.
    "k8s-mini-rtrox-io-cnpg-offsite" = { capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles"] }
    # Read-only, for restores: nothing in home-ops reads it day to day. A
    # Cluster restoring from the off-site copy (disaster recovery, or a restore
    # test) gets this one, so it can't write to or hide anything there. Kept on
    # purpose; don't remove it as unused.
    "k8s-mini-rtrox-io-cnpg-offsite-restore" = { capabilities = ["listBuckets", "listFiles", "readFiles"] }
  }
}

# Read by cluster-apps/mini/database/cnpg-offsite (ExternalSecret cnpg-offsite).
resource "doppler_secret" "cnpg_offsite_bucket" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "CNPG_OFFSITE_BACKBLAZE_BUCKET"
  value = jsonencode({
    application_key_id = module.cnpg_offsite_store.keys["k8s-mini-rtrox-io-cnpg-offsite"].application_key_id
    application_key    = module.cnpg_offsite_store.keys["k8s-mini-rtrox-io-cnpg-offsite"].application_key
    endpoint           = module.cnpg_offsite_store.bucket.endpoint
    bucket             = module.cnpg_offsite_store.bucket.name
  })
}

# Nothing in the cluster reads this one; it's there for a restore, by hand.
resource "doppler_secret" "cnpg_offsite_restore_bucket" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET"
  value = jsonencode({
    application_key_id = module.cnpg_offsite_store.keys["k8s-mini-rtrox-io-cnpg-offsite-restore"].application_key_id
    application_key    = module.cnpg_offsite_store.keys["k8s-mini-rtrox-io-cnpg-offsite-restore"].application_key
    endpoint           = module.cnpg_offsite_store.bucket.endpoint
    bucket             = module.cnpg_offsite_store.bucket.name
  })
}
