# Provider versions for this stack (Renovate bumps them and the lock file).
# The generated _providers.tf configures them; _backend.tf sets required_version.
terraform {
  required_providers {
    # The generated _providers.tf always configures doppler; nothing here
    # uses it until phase 3.
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.23.2"
    }
    # The same version terraform-record ran, so the move changes nothing.
    pocketid = {
      source  = "trozz/pocketid"
      version = "2.4.2"
    }
  }
}
