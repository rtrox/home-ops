# Provider versions for this stack (Renovate bumps them and the lock file).
# The generated _providers.tf configures them; _backend.tf sets required_version.
terraform {
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "0.14.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.23.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    # 2.x: the newest line that supports TrueNAS 25.04 (partly; tested in
    # migration P4-0). Move to 3.x after the upgrade to 25.10.
    truenas = {
      source  = "PjSalty/truenas"
      version = "2.4.1"
    }
  }
}
