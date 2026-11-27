# One Garage bucket (the NAS's S3 store) and the keys limited to it. The
# counterpart of object-store for Garage, with the same output shape, so a
# consumer's Doppler secret reads the same either way.
#
# Why a separate module and not a `backend` switch in object-store: a module
# that declares a provider forces every caller to configure it, even when its
# resources have count 0 (the garage provider's `host` and `token` are
# required, so a caller that never configures it fails to plan). object-store's
# callers (foundation, truenas) only use B2.
#
# The bucket's name is its global alias. Each key gets read and write on this
# bucket only, never owner (owner can change the bucket's settings and delete
# it). Garage's cluster layout stays out of Terraform. Rotate a key by adding a
# second one: a destroyed key's ID can't be re-imported, since Garage keeps
# tombstones.
resource "garage_bucket" "this" {
  global_alias = var.name

  lifecycle {
    # Deleting a bucket deletes its data. Never by Terraform.
    prevent_destroy = true
  }
}

resource "garage_key" "this" {
  for_each = var.keys

  name = each.key
}

resource "garage_bucket_key" "this" {
  for_each = var.keys

  bucket_id     = garage_bucket.this.id
  access_key_id = garage_key.this[each.key].access_key_id
  read          = true
  write         = true
  owner         = false
}
