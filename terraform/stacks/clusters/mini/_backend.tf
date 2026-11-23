// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  required_version = "~> 1.13"
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "stacks/clusters/mini/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
    use_path_style              = true
  }
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      enforced = true
      method   = method.aes_gcm.main
    }
    plan {
      enforced = true
      method   = method.aes_gcm.main
    }
  }
}
variable "state_passphrase" {
  sensitive = true
  type      = string
}
