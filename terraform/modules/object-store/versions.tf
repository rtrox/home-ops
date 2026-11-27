# The calling stack pins the exact versions (its versions.tf and lock file);
# this is the range the module is written for. Garage's provider is on the
# Terraform registry, not OpenTofu's.
terraform {
  required_version = "~> 1.13"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14"
    }
    garage = {
      source  = "registry.terraform.io/arsolitt/garagehq"
      version = "~> 1.3"
    }
  }
}
