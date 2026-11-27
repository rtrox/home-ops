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
variable "garage_admin_token" {
  sensitive = true
  type      = string
}
provider "garage" {
  host   = "s3.nas.rtrox.io:3903"
  scheme = "http"
  token  = var.garage_admin_token
}
