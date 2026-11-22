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

# Providers. Each stack lists what it needs in its stack.tm.hcl globals
# (providers, doppler_writes); these are the defaults and lookup tables.
# Versions are NOT generated: each stack pins them in its own versions.tf, so
# Renovate's terraform manager can bump them and their lock files.
globals {
  providers      = []
  doppler_writes = []

  # Doppler config -> the tf-at-home/prd secret holding its write token.
  # (Renamed with the Doppler projects after phase 4.)
  doppler_write_tokens = {
    "hosts-at-home/prd" = "DOPPLER_TRUENAS_WRITE_TOKEN"
    "k8s-at-home/min"   = "DOPPLER_MINI_WRITE_TOKEN"
    "tf-at-home/prd"    = "DOPPLER_TF_WRITE_TOKEN"
  }

  proxmox_endpoint = "https://pve.rtrox.io:8006/"
}

generate_hcl "_providers.tf" {
  content {
    # Reads provider credentials (token: DOPPLER_TOKEN in the environment).
    provider "doppler" {}

    data "doppler_secrets" "terraform" {
      project = "tf-at-home"
      config  = "prd"
    }

    # One alias per Doppler config the stack writes to, e.g. hosts-at-home/prd
    # becomes provider = doppler.hosts_at_home_prd.
    tm_dynamic "provider" {
      for_each = global.doppler_writes
      labels   = ["doppler"]
      attributes = {
        alias         = tm_replace(tm_replace(provider.value, "-", "_"), "/", "_")
        doppler_token = tm_hcl_expression("data.doppler_secrets.terraform.map.${global.doppler_write_tokens[provider.value]}")
      }
    }

    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "cloudflare") ? [1] : []
      labels   = ["cloudflare"]
      attributes = {
        api_token = tm_hcl_expression("data.doppler_secrets.terraform.map.CLOUDFLARE_TERRAFORM_TOKEN")
      }
    }

    # Proxmox's API token is written to hosts-at-home by the Ansible proxmox role.
    tm_dynamic "data" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["doppler_secrets", "hosts"]
      attributes = {
        project = "hosts-at-home"
        config  = "prd"
      }
    }

    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["proxmox"]
      attributes = {
        endpoint  = global.proxmox_endpoint
        api_token = tm_hcl_expression("data.doppler_secrets.hosts.map.PVE_TERRAFORM_API_TOKEN")
      }
    }
  }
}
