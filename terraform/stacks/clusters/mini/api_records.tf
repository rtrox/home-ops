# mini.rtrox.io: one A record per control-plane node, the name kubectl and
# talosctl reach the cluster's API by. DNS-only (an internal address),
# automatic TTL. The addresses come from inventory/hosts.yaml, so renumbering
# a node is an inventory edit (stack.tm.hcl watches the file).
locals {
  inventory_hosts = yamldecode(file("${path.module}/../../../../inventory/hosts.yaml"))

  # Every host defined under any group, keyed by its inventory name (as in the
  # dns stack's host_records.tf).
  inventory_all_hosts = merge([
    for group in values(local.inventory_hosts.all.children) :
    group.hosts if try(group.hosts, null) != null
  ]...)

  # Every mini node runs the control plane.
  api_record_name = "mini.rtrox.io"
  api_nodes       = ["node01.mini.rtrox.io", "node02.mini.rtrox.io", "node03.mini.rtrox.io"]
}

resource "cloudflare_dns_record" "api" {
  for_each = toset(local.api_nodes)

  zone_id = local.zone_id
  name    = local.api_record_name
  type    = "A"
  content = try(local.inventory_all_hosts[each.key].address, null)
  comment = "Mini Kubernetes API"
  proxied = false
  ttl     = 1

  lifecycle {
    precondition {
      # A valid IPv4 address: cidrhost parses it, and IPv6 (which it also
      # parses) is excluded. A missing host doesn't evaluate.
      condition = (
        can(cidrhost("${local.inventory_all_hosts[each.key].address}/32", 0)) &&
        !strcontains(try(local.inventory_all_hosts[each.key].address, ":"), ":")
      )
      error_message = "${each.key} is missing from inventory/hosts.yaml, or has no valid IPv4 address there. Fix the inventory, or remove the node from local.api_nodes."
    }
  }
}
