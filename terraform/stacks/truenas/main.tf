# What the two TrueNAS hosts need from outside themselves: their A records and
# the main TrueNAS's cloud-sync bucket. Moved from terraform-record's
# cloudflare and backblaze stacks in migration P2-5. Their ACME DNS-01 tokens
# are foundation's (truenas_acme_tokens.tf there).
#
# Written as plain resources keyed by host, so the architecture's `host`
# module (DNS records, ACME token, backup bucket) can later take them over
# with `moved` blocks: cloudflare_dns_record.host["<host>"] and
# module.nas_backup_bucket go into module.host["<host>"].
#
# The Doppler secret here is what the owner pastes into TrueNAS, in
# hosts-at-home/prd; renaming it loses that link.

# The zone is found by name, as the dns stack (which manages it) does.
data "cloudflare_zone" "rtrox_io" {
  filter = {
    name = "rtrox.io"
  }
}

locals {
  zone_id = data.cloudflare_zone.rtrox_io.zone_id

  # Host (its inventory/hosts.yaml name) -> what this stack keeps for it. The
  # comments are kept as they are live (typo included), so the import changes
  # nothing.
  truenas_hosts = {
    "nas.rtrox.io"    = { comment = "Main TrueNAs" }
    "backup.rtrox.io" = { comment = "Backup TrueNAS" }
  }
}
