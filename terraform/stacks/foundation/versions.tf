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
    # object-store declares it; not configured here (its resources have count 0
    # with backend b2). On the Terraform registry, not OpenTofu's.
    garage = {
      source  = "registry.terraform.io/arsolitt/garagehq"
      version = "1.3.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}
