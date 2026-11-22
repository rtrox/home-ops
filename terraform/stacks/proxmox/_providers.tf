// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
data "doppler_secrets" "terraform" {
  config  = "prd"
  project = "tf-at-home"
}
provider "cloudflare" {
  api_token = data.doppler_secrets.terraform.map.CLOUDFLARE_TERRAFORM_TOKEN
}
variable "doppler_hosts_token" {
  default   = null
  sensitive = true
  type      = string
}
provider "doppler" {
  alias         = "hosts"
  doppler_token = var.doppler_hosts_token
}
data "doppler_secrets" "hosts" {
  config   = "prd"
  project  = "hosts-at-home"
  provider = doppler.hosts
}
provider "proxmox" {
  api_token = data.doppler_secrets.hosts.map.PVE_TERRAFORM_API_TOKEN
  endpoint  = "https://pve.rtrox.io:8006/"
}
