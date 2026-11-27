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
  source = "../../../modules/garage-store"

  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.VOLSYNC_LOCAL_BUCKET
  keys     = { (local.garage_buckets.VOLSYNC_LOCAL_BUCKET) = {} }
}

module "garage_cnpg" {
  source = "../../../modules/garage-store"

  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.CNPG_LOCAL_BUCKET
  keys     = { (local.garage_buckets.CNPG_LOCAL_BUCKET) = {} }
}

module "garage_thanos" {
  source = "../../../modules/garage-store"

  endpoint = local.garage_s3_endpoint
  name     = local.garage_buckets.THANOS_LOCAL_BUCKET
  keys     = { (local.garage_buckets.THANOS_LOCAL_BUCKET) = {} }
}

module "garage_sure" {
  source = "../../../modules/garage-store"

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

# Same shape as VOLSYNC_BACKBLAZE_BUCKET (endpoint is a full URL, scheme
# included), plus region. The MinIO keys' endpoint is host:port, and their
# consumers add `http://` themselves (Thanos takes host:port only), so each
# cutover changes its template, not just the key name. Garage wants requests
# signed for region "garage" and path-style addressing (no root_domain).
resource "doppler_secret" "garage_bucket" {
  for_each = local.garage_modules
  provider = doppler.k8s_at_home_min

  lifecycle {
    # The provider only knows a key's secret from its create (or an import
    # with the secret): never write an empty key over a live secret.
    precondition {
      condition = (
        try(length(each.value.keys[local.garage_buckets[each.key]].application_key_id), 0) > 0 &&
        try(length(each.value.keys[local.garage_buckets[each.key]].application_key), 0) > 0
      )
      error_message = "The Garage key for ${each.key} has no ID or secret in state; don't write it to Doppler."
    }
  }

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
