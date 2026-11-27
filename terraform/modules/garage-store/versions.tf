# The calling stack pins the exact version (its versions.tf and lock file);
# this is the range the module is written for. Garage's provider is on the
# Terraform registry, not OpenTofu's.
terraform {
  required_version = "~> 1.13"

  required_providers {
    garage = {
      source  = "registry.terraform.io/arsolitt/garagehq"
      version = "~> 1.3"
    }
  }
}
