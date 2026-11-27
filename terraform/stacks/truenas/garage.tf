# Garage v2 (S3 storage that replaces MinIO), a TrueNAS custom app on the main
# NAS: one node, replication factor 1 (migration P4-1). Buckets and keys are
# later (P4-2), and the cluster layout isn't Terraform's: `server
# --single-node` lays the node out itself (the garagehq provider's
# `garage_node` fails on v2.6.0).
#
# The endpoint is http://s3.nas.rtrox.io:3900. The admin API (3903, which the
# garagehq provider needs later, and /metrics) is published too; RPC (3901)
# stays inside the container.
#
# Two datasets, both prevent_destroy: the data on rusty (the HDD pool), the
# metadata (an LMDB database, which wants fast storage) on zippy (the SSD
# pool). MinIO's data lives in an ixVolume, which TrueNAS deletes with its app,
# hence a dataset of our own. The app mounts them as bind mounts, so removing
# the app never removes data (remove_ix_volumes stays at its default, false).
#
# **A plan that destroys or replaces truenas_dataset.garage_* is a mistake:**
# a change of `pool` or `name` is a replace, which prevent_destroy refuses.
#
# Secrets: the RPC secret (32 bytes, hex) and the admin and metrics tokens are
# generated here, passed as environment variables (garage.toml has none) and
# written to Doppler hosts-at-home/prd. They are in the compose, so also in
# this stack's state (encrypted; CI can read it, see README.md).
#
# Updating the compose is an in-place update (custom_compose). app_name,
# catalog_app, train and version force a replace; only app_name is set, so
# never rename the app.
# Plan after any Garage upgrade (a new image digest here), see README.md.

resource "truenas_dataset" "garage_data" {
  pool        = "rusty"
  name        = "garage"
  share_type  = "APPS"
  record_size = "1M" # objects are large; fewer, bigger records

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_dataset" "garage_meta" {
  pool        = "zippy"
  name        = "garage-meta"
  share_type  = "APPS"
  record_size = "16K" # small records suit an LMDB database

  lifecycle {
    prevent_destroy = true
  }
}

# RPC secret: 32 bytes as 64 hex characters, what Garage requires.
# random_bytes, not random_id: random_id's attributes aren't sensitive, and its
# id (the secret in base64) is printed in plan and apply progress lines.
resource "random_bytes" "garage_rpc_secret" {
  length = 32
}

# No symbols in the tokens: Compose would treat a `$` as interpolation.

resource "random_password" "garage_admin_token" {
  length  = 48
  special = false
}

resource "random_password" "garage_metrics_token" {
  length  = 48
  special = false
}

locals {
  garage_image = "dxflrs/garage:v2.6.0@sha256:4b5a318fc9fe2fbec5d3af590eeafe05d83492e6411266fa0b9e215c20264013"

  # No secrets: the RPC secret and both tokens come from the environment.
  garage_toml = <<-EOT
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "lmdb"
    # One copy and no other node to repair from: fsync both, and snapshot the
    # metadata (Garage recommends it for LMDB; snapshots go in metadata_dir).
    metadata_fsync = true
    data_fsync = true
    metadata_auto_snapshot_interval = "6h"

    replication_factor = 1

    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "127.0.0.1:3901"

    [s3_api]
    s3_region = "garage"
    api_bind_addr = "[::]:3900"

    [admin]
    api_bind_addr = "[::]:3903"
  EOT

  garage_compose = {
    services = {
      garage = {
        image   = local.garage_image
        command = ["/garage", "server", "--single-node"]
        # The apps user, which the APPS dataset preset gives access to.
        user    = "568:568"
        restart = "unless-stopped"
        environment = {
          GARAGE_RPC_SECRET    = random_bytes.garage_rpc_secret.hex
          GARAGE_ADMIN_TOKEN   = sensitive(random_password.garage_admin_token.result)
          GARAGE_METRICS_TOKEN = sensitive(random_password.garage_metrics_token.result)
        }
        ports = [
          "3900:3900",
          "3903:3903",
        ]
        volumes = [
          "${truenas_dataset.garage_meta.mount_point}:/var/lib/garage/meta",
          "${truenas_dataset.garage_data.mount_point}:/var/lib/garage/data",
        ]
        configs = [
          { source = "garage_toml", target = "/etc/garage.toml" },
        ]
      }
    }
    configs = {
      garage_toml = { content = local.garage_toml }
    }
  }
}

resource "truenas_app" "garage" {
  app_name       = "garage"
  custom_compose = yamlencode(local.garage_compose)

  depends_on = [
    truenas_dataset.garage_data,
    truenas_dataset.garage_meta,
  ]
}

# The S3 endpoint's name: s3.nas.rtrox.io -> the NAS's address (inventory, so
# the NAS's move back to the house is an inventory edit, as in records.tf).
resource "cloudflare_dns_record" "garage_s3" {
  zone_id = local.zone_id
  name    = "s3.nas.rtrox.io"
  type    = "A"
  content = try(local.inventory_all_hosts["nas.rtrox.io"].address, null)
  comment = "Garage S3 API on the NAS"
  proxied = false
  ttl     = 1

  lifecycle {
    precondition {
      condition = (
        can(cidrhost("${local.inventory_all_hosts["nas.rtrox.io"].address}/32", 0)) &&
        !strcontains(try(local.inventory_all_hosts["nas.rtrox.io"].address, ":"), ":")
      )
      error_message = "nas.rtrox.io is missing from inventory/hosts.yaml, or has no valid IPv4 address there."
    }
  }
}

resource "doppler_secret" "garage_admin_token" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "GARAGE_ADMIN_TOKEN"
  value   = random_password.garage_admin_token.result
}

resource "doppler_secret" "garage_rpc_secret" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "GARAGE_RPC_SECRET"
  value   = random_bytes.garage_rpc_secret.hex
}

resource "doppler_secret" "garage_metrics_token" {
  provider = doppler.hosts_at_home_prd

  project = "hosts-at-home"
  config  = "prd"
  name    = "GARAGE_METRICS_TOKEN"
  value   = random_password.garage_metrics_token.result
}
