# Mini's buckets on Garage (the NAS's S3 store, truenas stack's garage.tf):
# volsync's local restic repositories, CNPG's WAL and base backups, Thanos's
# blocks and Sure's uploads. Same names as their MinIO buckets, one key each
# (named after its bucket) with read and write on that bucket only.
#
# Each bucket's Doppler secret is a backend-neutral key (*_LOCAL_BUCKET). The
# consumers still read the *_MINIO_BUCKET keys until their cutovers; nothing
# reads these yet. Garage's layout (nodes, capacity) is not in Terraform.
#
# Applied from the laptop (the stack is ci-skip). The garage provider reaches
# the admin API on the NAS, which CI's runner can't yet.
locals {
  garage_s3_endpoint = "http://s3.nas.rtrox.io:3900"
  garage_region      = "garage"

  # Doppler key -> bucket. The key is named after its bucket.
  garage_buckets = {
    VOLSYNC_LOCAL_BUCKET = "k8s-rtrox-io-volsync-store"
    CNPG_LOCAL_BUCKET    = "k8s-rtrox-io-mini-cnpg"
    THANOS_LOCAL_BUCKET  = "k8s-rtrox-io-mini-thanos"
    SURE_LOCAL_BUCKET    = "k8s-rtrox-io-mini-sure"
  }
}

module "garage_volsync" {
  source = "../../../modules/object-store"

  backend  = "garage"
  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.VOLSYNC_LOCAL_BUCKET
  keys     = { (local.garage_buckets.VOLSYNC_LOCAL_BUCKET) = {} }
}

module "garage_cnpg" {
  source = "../../../modules/object-store"

  backend  = "garage"
  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.CNPG_LOCAL_BUCKET
  keys     = { (local.garage_buckets.CNPG_LOCAL_BUCKET) = {} }
}

module "garage_thanos" {
  source = "../../../modules/object-store"

  backend  = "garage"
  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.THANOS_LOCAL_BUCKET
  keys     = { (local.garage_buckets.THANOS_LOCAL_BUCKET) = {} }
}

module "garage_sure" {
  source = "../../../modules/object-store"

  backend  = "garage"
  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.SURE_LOCAL_BUCKET
  keys     = { (local.garage_buckets.SURE_LOCAL_BUCKET) = {} }
}

locals {
  garage_modules = {
    VOLSYNC_LOCAL_BUCKET = module.garage_volsync
    CNPG_LOCAL_BUCKET    = module.garage_cnpg
    THANOS_LOCAL_BUCKET  = module.garage_thanos
    SURE_LOCAL_BUCKET    = module.garage_sure
  }
}

# Same shape as VOLSYNC_BACKBLAZE_BUCKET and the MinIO keys, plus region (the
# S3 clients need it; Garage's is "garage").
resource "doppler_secret" "garage_bucket" {
  for_each = local.garage_modules
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = each.key
  value = jsonencode({
    application_key_id = each.value.keys[local.garage_buckets[each.key]].application_key_id
    application_key    = each.value.keys[local.garage_buckets[each.key]].application_key
    endpoint           = each.value.bucket.endpoint
    bucket             = each.value.bucket.name
    region             = local.garage_region
  })
}
