# pve.rtrox.io's A record. DNS-only (an internal address), automatic TTL. Name
# and content come from inventory/hosts.yaml, as the truenas and dns stacks'
# host records do, so renumbering the host is an inventory edit (stack.tm.hcl
# watches the file). Moved from terraform-record's cloudflare stack.
locals {
  pve_host = try(local.inventory_groups.proxmox.hosts["pve.rtrox.io"], null)
}

resource "cloudflare_dns_record" "pve" {
  zone_id = data.cloudflare_zone.rtrox_io.zone_id
  name    = try(local.pve_host.dns_name, null)
  type    = "A"
  content = try(local.pve_host.address, null)
  comment = "Proxmox VE host"
  proxied = false
  ttl     = 1

  lifecycle {
    # This stack's own provider reaches Proxmox by this name.
    prevent_destroy = true

    # A missing host fails both: its address and dns_name don't evaluate.
    precondition {
      # A valid IPv4 address: cidrhost parses it, and IPv6 (which it also
      # parses) is excluded.
      condition     = can(cidrhost("${local.pve_host.address}/32", 0)) && !strcontains(try(local.pve_host.address, ":"), ":")
      error_message = "pve.rtrox.io is missing from inventory/hosts.yaml's proxmox group, or has no valid IPv4 address there."
    }
    precondition {
      condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.rtrox\\.io$", local.pve_host.dns_name))
      error_message = "pve.rtrox.io is missing from inventory/hosts.yaml's proxmox group, or has no dns_name in the rtrox.io zone there."
    }
  }
}
