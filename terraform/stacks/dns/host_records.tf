# Host A records, parked here. They belong with their hosts, and all five move
# to the network stack in phase 6 with the hosts' DHCP leases and the ZTNet
# droplet (owner decision, 2026-11-23). Moved from terraform-record's
# cloudflare stack (migration P2-2c). Like records.tf: DNS-only, automatic TTL,
# fully qualified names.

# The house's network-service hosts, from inventory/hosts.yaml: the record's
# name is the host's dns_name and its content the host's address, so
# renumbering one is an inventory edit (stack.tm.hcl watches the file).
# avahi's Pi is offline (the inventory's `offline` group), but its name and
# address stay reserved, so its record stays.
locals {
  inventory_hosts = yamldecode(file("${path.module}/../../../inventory/hosts.yaml"))

  # Every host defined under any group, keyed by its inventory name. Parent
  # groups (pis, offline, vms) only list children, so each host is defined
  # once. (Filtered rather than coalesce(..., {}): the groups' hosts objects
  # have different attributes, so they don't share a type with {}.)
  inventory_all_hosts = merge([
    for group in values(local.inventory_hosts.all.children) :
    group.hosts if try(group.hosts, null) != null
  ]...)

  # Inventory hostname -> the record's comment, kept as it is live so the
  # import changes nothing.
  inventory_host_records = {
    "ns1.rtrox.io"   = "Blocky NS 1"
    "ns2.rtrox.io"   = "Blocky NS 2"
    "avahi.rtrox.io" = "Avahi Reflector"
    "unifi.rtrox.io" = "Unifi Controller"
  }
}

resource "cloudflare_dns_record" "inventory_host" {
  for_each = local.inventory_host_records

  zone_id = module.zone["rtrox.io"].zone_id
  name    = try(local.inventory_all_hosts[each.key].dns_name, null)
  type    = "A"
  content = try(local.inventory_all_hosts[each.key].address, null)
  comment = each.value
  proxied = false
  ttl     = 1

  lifecycle {
    precondition {
      condition     = contains(keys(local.inventory_all_hosts), each.key)
      error_message = "${each.key} is not a host in inventory/hosts.yaml, so its A record has no address. Add it back, or remove it from local.inventory_host_records."
    }
    precondition {
      condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", local.inventory_all_hosts[each.key].address))
      error_message = "${each.key} has no IPv4 address in inventory/hosts.yaml."
    }
    precondition {
      condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.rtrox\\.io$", local.inventory_all_hosts[each.key].dns_name))
      error_message = "${each.key} has no dns_name in the rtrox.io zone in inventory/hosts.yaml."
    }
  }
}

# The DigitalOcean droplet running the ZTNet controller. Not in the inventory
# (it's on no site's network).
resource "cloudflare_dns_record" "ztnet" {
  zone_id = module.zone["rtrox.io"].zone_id
  name    = "ztnet.rtrox.io"
  type    = "A"
  content = "146.190.167.99"
  comment = "ZTNet Controller"
  proxied = false
  ttl     = 1
}
