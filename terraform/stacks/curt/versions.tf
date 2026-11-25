# Provider versions for this stack (Renovate bumps them and the lock file).
# The generated _providers.tf configures them; _backend.tf sets required_version.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
    # Unused, but the generated _providers.tf configures it in every stack.
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.23.2"
    }
  }
}
