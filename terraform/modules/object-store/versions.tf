# The calling stack pins the exact versions (its versions.tf and lock file);
# this is the range the module is written for.
terraform {
  required_version = "~> 1.13"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14"
    }
  }
}
