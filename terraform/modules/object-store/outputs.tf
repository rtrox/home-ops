output "bucket" {
  description = "The bucket's ID and name, and the S3 endpoint of the account it's in."
  value = {
    id       = b2_bucket.this.bucket_id
    name     = b2_bucket.this.bucket_name
    endpoint = data.b2_account_info.current.s3_api_url
  }
}

output "keys" {
  description = "Key name -> {application_key_id, application_key}."
  value = {
    for name, key in b2_application_key.this : name => {
      application_key_id = key.application_key_id
      application_key    = key.application_key
    }
  }
  sensitive = true
}
