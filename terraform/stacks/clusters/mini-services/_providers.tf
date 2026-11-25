// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
variable "doppler_write_token_k8s_at_home_min_ci" {
  sensitive = true
  type      = string
}
provider "doppler" {
  alias         = "k8s_at_home_min_ci"
  doppler_token = var.doppler_write_token_k8s_at_home_min_ci
}
provider "pocketid" {
  base_url = "https://auth.rtrox.io"
}
