# The calling stack pins the exact versions (its versions.tf and lock file);
# this is the range the module is written for.
terraform {
  required_version = "~> 1.13"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.29"
    }
  }
}
