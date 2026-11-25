# What mini needs from outside the cluster to boot and run. Moved from
# terraform-record's cloudflare and backblaze stacks in migration P2-3.
# The architecture's `k8s-cluster` module is extracted from
# these files, with moved blocks, when a second cluster needs the same things.
#
# The Doppler secrets here are what the cluster's ExternalSecrets read, in
# k8s-at-home/min; renaming one breaks its consumer.

# The zone is found by name, as the dns stack (which manages it) and the
# proxmox stack do. The account comes with it: the stack's token has no
# account-level permission that lists accounts.
data "cloudflare_zone" "rtrox_io" {
  filter = {
    name = "rtrox.io"
  }
}

locals {
  account_id = data.cloudflare_zone.rtrox_io.account.id
  zone_id    = data.cloudflare_zone.rtrox_io.zone_id
}
