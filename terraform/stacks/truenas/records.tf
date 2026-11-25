# One A record per TrueNAS host. DNS-only (an internal address), automatic
# TTL. The name is the host's dns_name and the content its address, both from
# inventory/hosts.yaml, so renumbering a host (the NAS's move back to the
# house, its `moves_to`) is an inventory edit (stack.tm.hcl watches the file).
locals {
  inventory_hosts = yamldecode(file("${path.module}/../../../inventory/hosts.yaml"))

  # Every host defined under any group, keyed by its inventory name (as in the
  # dns stack's host_records.tf).
  inventory_all_hosts = merge([
    for group in values(local.inventory_hosts.all.children) :
    group.hosts if try(group.hosts, null) != null
  ]...)
}

resource "cloudflare_dns_record" "host" {
  for_each = local.truenas_hosts

  zone_id = local.zone_id
  name    = try(local.inventory_all_hosts[each.key].dns_name, null)
  type    = "A"
  content = try(local.inventory_all_hosts[each.key].address, null)
  comment = each.value.comment
  proxied = false
  ttl     = 1

  lifecycle {
    # A missing host fails both: its address and dns_name don't evaluate.
    precondition {
      # A valid IPv4 address: cidrhost parses it, and IPv6 (which it also
      # parses) is excluded.
      condition = (
        can(cidrhost("${local.inventory_all_hosts[each.key].address}/32", 0)) &&
        !strcontains(try(local.inventory_all_hosts[each.key].address, ":"), ":")
      )
      error_message = "${each.key} is missing from inventory/hosts.yaml, or has no valid IPv4 address there. Fix the inventory, or remove the host from local.truenas_hosts."
    }
    precondition {
      condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.rtrox\\.io$", local.inventory_all_hosts[each.key].dns_name))
      error_message = "${each.key} is missing from inventory/hosts.yaml, or has no dns_name in the rtrox.io zone there."
    }
  }
}
