# Passwords for the DNS hosts, generated here and written to Doppler: Ansible
# reads ansible/prd (task ansible:*), and Blocky in mini reads the apartment's
# Valkey password from k8s-at-home/min-ci (secrets written by stacks CI plans
# live there, read through the doppler-ci store).
#
# They are in this stack's (encrypted) state, so state is the only other place
# they exist. Nothing here regenerates them by accident: ignore_changes = all
# means editing an argument never replaces one. Rotating is deliberate:
#   tofu apply -replace=random_password.valkey_house
# (a replace waits for owner approval in CI). There is no prevent_destroy, so
# -replace works.
#
# Rollout facts:
# - Blocky's Valkey is `required: false`, so a wrong password only loses the
#   shared cache and blocking state; DNS keeps answering.
# - ns1 and ns2 with different VRRP passwords each ignore the other's
#   advertisements and both claim the VIP until both have the new one.
# - Hosts change only when the owner runs Ansible; dns-a2 (Blocky in mini)
#   switches by itself once Flux has reconciled the new BLOCKY_APARTMENT.

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
