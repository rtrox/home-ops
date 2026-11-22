# State: one R2 bucket, one key per stack. The endpoint and credentials are NOT
# here: they come from Doppler (R2_STATE_READWRITE) as AWS_ENDPOINT_URL_S3,
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, set by task tf:*.
globals "backend" {
  bucket = "tofu-state"
  region = "auto"
}

generate_hcl "_backend.tf" {
  content {
    terraform {
      # OpenTofu; the exact version is pinned in .mise.toml.
      required_version = "~> 1.13"

      backend "s3" {
        bucket       = global.backend.bucket
        key          = "${tm_trimprefix(terramate.stack.path.absolute, "/terraform/")}/terraform.tfstate"
        region       = global.backend.region
        use_lockfile = true

        # R2 speaks S3 but isn't AWS: skip the AWS-only checks.
        use_path_style              = true
        skip_credentials_validation = true
        skip_region_validation      = true
        skip_requesting_account_id  = true
        skip_metadata_api_check     = true
        skip_s3_checksum            = true
      }

      # Every stack's state and plans are encrypted. The passphrase comes from
      # Doppler (TOFU_STATE_PASSPHRASE) as TF_VAR_state_passphrase.
      encryption {
        key_provider "pbkdf2" "main" {
          passphrase = var.state_passphrase
        }
        method "aes_gcm" "main" {
          keys = key_provider.pbkdf2.main
        }
        state {
          method   = method.aes_gcm.main
          enforced = true
        }
        plan {
          method   = method.aes_gcm.main
          enforced = true
        }
      }
    }

    variable "state_passphrase" {
      type      = string
      sensitive = true
    }
  }
}
