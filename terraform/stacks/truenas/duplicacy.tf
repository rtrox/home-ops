# Duplicacy's bucket on Garage (this stack's own Garage, garage.tf): the same
# name as its MinIO bucket (rtrox-duplicacy), one key named after it with read
# and write on that bucket only (the garage-store module).
#
# The key goes to Doppler hosts-at-home/prd as DUPLICACY_LOCAL_BUCKET. Nothing
# reads it yet: Duplicacy still uses RTROX_DUPLICACY (the MinIO key, which
# terraform-record's minio stack writes), pasted into TrueNAS by hand, until the
# Duplicacy cutover. This stack never touches RTROX_DUPLICACY.
#
# The garage provider (the admin API, s3.nas.rtrox.io:3903) talks to the Garage
# that garage.tf runs: see README.md ("Garage (S3)") for a fresh apply.
locals {
  duplicacy_s3_endpoint = "http://s3.nas.rtrox.io:3900"
  duplicacy_region      = "garage"
  duplicacy_bucket      = "rtrox-duplicacy"
}

module "garage_duplicacy" {
  source = "../../modules/garage-store"

  endpoint = local.duplicacy_s3_endpoint
  name     = local.duplicacy_bucket
  keys     = { (local.duplicacy_bucket) = {} }

  depends_on = [truenas_app.garage]
}

# {application_key_id, application_key, endpoint, bucket, region}, the shape of
# clusters/mini's *_LOCAL_BUCKET keys (endpoint a full URL; Garage wants region
# "garage" and path-style requests).
resource "doppler_secret" "duplicacy_local_bucket" {
  provider = doppler.hosts_at_home_prd

  lifecycle {
    # The provider only knows a key's secret from its create (or an import
    # with the secret): never write an empty key over a live secret.
    precondition {
      condition = (
        try(length(module.garage_duplicacy.keys[local.duplicacy_bucket].application_key_id), 0) > 0 &&
        try(length(module.garage_duplicacy.keys[local.duplicacy_bucket].application_key), 0) > 0
      )
      error_message = "The Garage key for DUPLICACY_LOCAL_BUCKET has no ID or secret in state; don't write it to Doppler."
    }
  }

  project = "hosts-at-home"
  config  = "prd"
  name    = "DUPLICACY_LOCAL_BUCKET"
  value = jsonencode({
    application_key_id = module.garage_duplicacy.keys[local.duplicacy_bucket].application_key_id
    application_key    = module.garage_duplicacy.keys[local.duplicacy_bucket].application_key
    endpoint           = module.garage_duplicacy.bucket.endpoint
    bucket             = module.garage_duplicacy.bucket.name
    region             = local.duplicacy_region
  })
}
