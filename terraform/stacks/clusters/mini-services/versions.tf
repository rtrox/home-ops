# Provider versions for this stack (Renovate bumps them and the lock file).
# The generated _providers.tf configures them; _backend.tf sets required_version.
terraform {
  required_providers {
    # Writes the infra.yaml clients' secrets to k8s-at-home/min-ci (infra.tf).
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.23.2"
    }
    # App secrets it generates (paperless.tf).
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    # Moved from trozz/pocketid (an archive since Nov 2026, same builds).
    pocketid = {
      source  = "pocket-id/pocketid"
      version = "2.5.0"
    }
  }
}
