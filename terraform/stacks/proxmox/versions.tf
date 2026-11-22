# Provider versions for this stack (Renovate bumps them and the lock file).
# The generated _providers.tf configures them; _backend.tf sets required_version.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.23.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}
