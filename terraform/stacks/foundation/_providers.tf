// TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "doppler" {
}
variable "doppler_config" {
  default = "prd"
  type    = string
}
data "doppler_secrets" "terraform" {
  config  = var.doppler_config
  project = "tf-at-home"
}
provider "cloudflare" {
  api_token = data.doppler_secrets.terraform.map.CLOUDFLARE_TERRAFORM_TOKEN
}
