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
  #
  # NOTE for CI (var.doppler_config = "ci"): a stack with doppler_writes needs
  # these same key names in tf-at-home/ci, holding READ-ONLY tokens, or its
  # plan can't configure the aliased providers. The proxmox stack has none.
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

    # Which config the Doppler reads use. "prd" on the laptop; CI sets
    # TF_VAR_doppler_config=ci, a separate root config in each project holding
    # only what a plan needs, read with tokens scoped to it.
    variable "doppler_config" {
      type    = string
      default = "prd"
    }

    data "doppler_secrets" "terraform" {
      project = "tf-at-home"
      config  = var.doppler_config
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
    #
    # The hosts-at-home read goes through its own provider alias, "hosts", so it
    # can use a different token from the tf-at-home read above. CI's service
    # tokens each read one Doppler config only. var.doppler_hosts_token is
    # unset on the laptop (null), and the provider then falls back to
    # DOPPLER_TOKEN, the CLI token that reads both projects. In CI it's set
    # (TF_VAR_doppler_hosts_token) to the hosts-at-home/ci read token, while
    # DOPPLER_TOKEN is the tf-at-home/ci one.
    tm_dynamic "variable" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["doppler_hosts_token"]
      attributes = {
        type      = tm_hcl_expression("string")
        default   = tm_hcl_expression("null")
        sensitive = true
      }
    }

    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["doppler"]
      attributes = {
        alias         = "hosts"
        doppler_token = tm_hcl_expression("var.doppler_hosts_token")
      }
    }

    tm_dynamic "data" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["doppler_secrets", "hosts"]
      attributes = {
        provider = tm_hcl_expression("doppler.hosts")
        project  = "hosts-at-home"
        config   = tm_hcl_expression("var.doppler_config")
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
