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
data "doppler_secrets" "hosts" {
  config  = "prd"
  project = "hosts-at-home"
}
provider "proxmox" {
  api_token = data.doppler_secrets.hosts.map.PVE_TERRAFORM_API_TOKEN
  endpoint  = "https://pve.rtrox.io:8006/"
}
