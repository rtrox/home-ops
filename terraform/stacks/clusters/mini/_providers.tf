// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
variable "doppler_write_token_k8s_at_home_min" {
  sensitive = true
  type      = string
}
provider "doppler" {
  alias         = "k8s_at_home_min"
  doppler_token = var.doppler_write_token_k8s_at_home_min
}
provider "cloudflare" {
}
provider "b2" {
}
