// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
variable "doppler_write_token_hosts_at_home_prd" {
  sensitive = true
  type      = string
}
provider "doppler" {
  alias         = "hosts_at_home_prd"
  doppler_token = var.doppler_write_token_hosts_at_home_prd
}
provider "cloudflare" {
}
provider "b2" {
}
provider "truenas" {
  url = "https://nas.rtrox.io"
}
