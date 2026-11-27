output "bucket" {
  description = "The bucket's ID and name, and the S3 endpoint it's reached at (the B2 account's, or the Garage `endpoint` input)."
  value = {
    id       = local.b2 ? b2_bucket.this[0].bucket_id : garage_bucket.this[0].id
    name     = local.b2 ? b2_bucket.this[0].bucket_name : garage_bucket.this[0].global_alias
    endpoint = local.b2 ? data.b2_account_info.current[0].s3_api_url : var.endpoint
  }
}

output "keys" {
  description = "Key name -> {application_key_id, application_key}."
  value = local.b2 ? {
    for name, key in b2_application_key.this : name => {
      application_key_id = key.application_key_id
      application_key    = key.application_key
    }
    } : {
    for name, key in garage_key.this : name => {
      application_key_id = key.access_key_id
      application_key    = key.secret_access_key
    }
  }
  sensitive = true
}
