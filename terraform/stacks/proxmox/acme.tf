# Trusted certificate for pve.rtrox.io from Let's Encrypt, DNS-01 through
# Cloudflare. The plugin's token is issued in acme_token.tf and passed straight
# in: it's created and consumed in this stack, so it never goes through Doppler.
#
# The Let's Encrypt account itself is registered by Ansible (role `proxmox`,
# tasks/acme.yaml): Proxmox only lets root@pam create ACME accounts, and an API
# token gets a 403 even with the Administrator role.
#
# Both resources came over from terraform-record's proxmox stack at these same
# addresses (see MIGRATION.md), so don't rename them.
locals {
  acme_account = "letsencrypt"
}

resource "proxmox_acme_dns_plugin" "cloudflare" {
  plugin = "cloudflare"
  api    = "cf"
  data = {
    CF_Token = cloudflare_api_token.pve_acme.value
  }
}

resource "proxmox_acme_certificate" "pve" {
  node_name = "pve"
  account   = local.acme_account

  domains = [
    {
      domain = "pve.rtrox.io"
      plugin = proxmox_acme_dns_plugin.cloudflare.plugin
    },
  ]

  # Proxmox renews this itself (pve-daily-update, inside 30 days of expiry).
  # Destroying it would drop the host back to its self-signed certificate and
  # spend a Let's Encrypt order to get it back, so a plan that wants to is a bug.
  lifecycle {
    prevent_destroy = true
  }
}
