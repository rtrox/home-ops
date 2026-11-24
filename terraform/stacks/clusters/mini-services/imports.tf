# Migration P2-4: what this stack adopts from terraform-record's pocketid stack,
# which forgets it first (removed, destroy = false). See MIGRATION.md. Delete
# this file, p2-4-plan.json and MIGRATION.md in the cleanup PR once the
# zero-diff gate passes.
#
# The groups and clients are imported by ID, found by name with a lookup, so
# no ID is written down here. A lookup fails the plan, rather than importing
# the wrong object or creating one, if a name is missing (Invalid index) or
# belongs to more than one object (one() on a longer list). The lists hold
# names, URLs and group IDs, never a secret.
#
# The Doppler secrets terraform-record built from client secrets
# (SURE_POCKETID_CLIENT, ACTUAL_POCKETID_CLIENT) are not imported: their
# secrets can't be read back, so terraform-record lets them go and phase 3
# rotates them.

data "pocketid_groups" "imported" {}

data "pocketid_clients" "imported" {}

locals {
  imported_group_ids  = { for g in data.pocketid_groups.imported.groups : g.name => g.id... }
  imported_client_ids = { for c in data.pocketid_clients.imported.clients : c.name => c.id... }
}

import {
  for_each = local.groups
  to       = pocketid_group.this[each.key]
  id       = one(local.imported_group_ids[each.key])
}

import {
  for_each = local.clients
  to       = pocketid_client.this[each.key]
  id       = one(local.imported_client_ids[each.value.name])
}
