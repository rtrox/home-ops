# Migration P2-2c: the five host records adopted from terraform-record's
# cloudflare stack, which forgets them (moved, then removed with
# destroy = false) and must be applied first. Delete this file in the cleanup
# PR once both stacks plan No changes.
#
# The first import iterates over local.inventory_host_records, so a host
# without an ID below fails the plan instead of planning a create.

import {
  for_each = local.inventory_host_records
  to       = cloudflare_dns_record.inventory_host[each.key]
  id       = "${local.imported_host_zone_id}/${local.imported_host_record_ids[each.key]}"
}

import {
  to = cloudflare_dns_record.ztnet
  id = "${local.imported_host_zone_id}/94aac50447c09e83710c0fac94daff4e"
}

# Cloudflare IDs (not secrets), from terraform-record cloudflare's state.
locals {
  imported_host_zone_id = "9aedc7db6baa3b7dffd1e1ef54f7b7d2" # rtrox.io
  imported_host_record_ids = {
    "ns1.rtrox.io"   = "87d9fbaa4929d6fea96c37b66e2cb730"
    "ns2.rtrox.io"   = "33f8729348148c8c7999ed625ea7a1fb"
    "avahi.rtrox.io" = "28e61b2c04a1937e16e9bff854884497"
    "unifi.rtrox.io" = "73ea432b28242d0ea34f8500048e6d0d"
  }
}
