output "bucket" {
  description = "The bucket's ID and name, and the S3 endpoint it's reached at."
  value = {
    id       = garage_bucket.this.id
    name     = garage_bucket.this.global_alias
    endpoint = var.endpoint
  }
}

output "keys" {
  description = "Key name -> {application_key_id, application_key}."
  value = {
    for name, key in garage_key.this : name => {
      application_key_id = key.access_key_id
      application_key    = key.secret_access_key
    }
  }
  sensitive = true
}
