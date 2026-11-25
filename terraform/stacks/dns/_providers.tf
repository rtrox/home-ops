// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
variable "doppler_write_token_ansible_prd" {
  sensitive = true
  type      = string
}
variable "doppler_write_token_k8s_at_home_min_ci" {
  sensitive = true
  type      = string
}
provider "doppler" {
  alias         = "ansible_prd"
  doppler_token = var.doppler_write_token_ansible_prd
}
provider "doppler" {
  alias         = "k8s_at_home_min_ci"
  doppler_token = var.doppler_write_token_k8s_at_home_min_ci
}
provider "cloudflare" {
}
