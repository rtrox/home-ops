# Passwords for the DNS hosts, generated here and written to Doppler: Ansible
# reads ansible/prd (task ansible:*), and Blocky in mini reads the apartment's
# Valkey password from k8s-at-home/min-ci (secrets written by stacks CI plans
# live there, read through the doppler-ci store).
#
# They are in this stack's (encrypted) state, so state is the only other place
# they exist. Nothing here regenerates them by accident: ignore_changes = all
# means editing an argument never replaces one. Rotating is deliberate:
# from the laptop (CI has no -replace):
#   task tf:apply STACK=dns -- -replace=random_password.valkey_house
# There is no prevent_destroy, so -replace works.
#
# Rollout facts:
# - Blocky's Valkey is `required: false`, so a wrong password only loses the
#   shared cache and blocking state; DNS keeps answering.
# - While ns1 and ns2 have different keepalived passwords they ignore each
#   other's IPv4 adverts. The IPv6 ones have no password and share a sync
#   group, so the backup should stay backup (not tested). Keep the gap short.
# - Hosts change only when the owner runs Ansible; dns-a2 (Blocky in mini)
#   switches by itself within an hour of the apply (its ExternalSecret's refresh).

# Alphanumeric only: Valkey's are quoted in valkey.conf and Blocky's YAML.
resource "random_password" "valkey_house" {
  length  = 40
  special = false

  lifecycle {
    ignore_changes = all
  }
}

resource "random_password" "valkey_apartment" {
  length  = 40
  special = false

  lifecycle {
    ignore_changes = all
  }
}

# VRRP's simple password auth uses only the first 8 characters.
resource "random_password" "keepalived_house" {
  length  = 8
  special = false

  lifecycle {
    ignore_changes = all
  }
}

resource "doppler_secret" "valkey_house" {
  provider = doppler.ansible_prd

  project = "ansible"
  config  = "prd"
  name    = "VALKEY_HOUSE_PASSWORD"
  value   = random_password.valkey_house.result
}

resource "doppler_secret" "valkey_apartment" {
  provider = doppler.ansible_prd

  project = "ansible"
  config  = "prd"
  name    = "VALKEY_APARTMENT_PASSWORD"
  value   = random_password.valkey_apartment.result
}

resource "doppler_secret" "keepalived_house" {
  provider = doppler.ansible_prd

  project = "ansible"
  config  = "prd"
  name    = "KEEPALIVED_HOUSE_PASSWORD"
  value   = random_password.keepalived_house.result
}

# dns-a2's copy, the JSON shape cluster-apps/mini/network/blocky reads.
resource "doppler_secret" "blocky_apartment" {
  provider = doppler.k8s_at_home_min_ci

  project = "k8s-at-home"
  config  = "min-ci"
  name    = "BLOCKY_APARTMENT"
  value   = jsonencode({ valkey_password = random_password.valkey_apartment.result })
}
