# OIDC clients declared by the apps themselves: every
# cluster-apps/mini/<namespace>/<app>/infra.yaml (see README.md). Separate from
# pocketid_client.this, which holds the hand-written clients in pocketid.tf and
# can't be destroyed: these have no prevent_destroy, so deleting an infra.yaml
# destroys its client. CI holds such an apply for the owner's approval (it
# destroys), which is the only guard.
#
# Each confidential client's id and secret go to k8s-at-home/min-ci as
# <APP>_POCKETID_CLIENT, the same JSON shape the hand-made secrets use. Public
# clients have no secret, so they get no Doppler entry.
#
# Files are checked strictly and a bad one fails the plan (the checks resource
# below), never gets skipped: an unreadable file that were ignored would plan
# the destruction of its app's client.

locals {
  infra_root = "${path.module}/../../../../cluster-apps/mini"

  infra_top_keys  = ["oidc"]
  infra_oidc_keys = ["callback", "groups", "name", "public"]

  # ** so a file at the wrong depth is found and reported, not ignored.
  infra_files = sort(tolist(fileset(local.infra_root, "**/infra.yaml")))

  # Per file, everything checked. try() only turns a failure into a flag that
  # the checks name; nothing is dropped silently.
  infra_info = [
    for f in local.infra_files : {
      file = "cluster-apps/mini/${f}"
      app  = basename(dirname(f))
      doc  = try(yamldecode(file("${local.infra_root}/${f}")), "INVALID")
    }
  ]

  infra_parsed = [
    for i in local.infra_info : merge(i, {
      depth_ok = length(split("/", trimprefix(i.file, "cluster-apps/mini/"))) == 3
      app_ok   = can(regex("^[a-z0-9-]+$", i.app))
      is_map   = try(length(keys(i.doc)) >= 0, false)
      top_keys = try(keys(i.doc), [])
      oidc     = try(i.doc.oidc, null)
    })
  ]

  infra_checked = [
    for i in local.infra_parsed : merge(i, {
      oidc_is_map = i.is_map && try(length(keys(i.oidc)) >= 0, false)
      oidc_keys   = try(keys(i.oidc), [])
    })
  ]

  infra_typed = [
    for i in local.infra_checked : merge(i, {
      callbacks = try(tolist(i.oidc.callback), [try(i.oidc.callback, null)])
      groups    = try(tolist(i.oidc.groups), [])
      name      = try(i.oidc.name, i.app)
      has_pub   = contains(i.oidc_keys, "public")
      public    = try(i.oidc.public, false)
    })
  ]

  # Problems, one string per file and fault, each naming the file.
  infra_file_problems = flatten([
    for i in local.infra_typed : concat(
      i.depth_ok ? [] : ["${i.file}: must be cluster-apps/mini/<namespace>/<app>/infra.yaml"],
      i.app_ok ? [] : ["${i.file}: the app directory name must match ^[a-z0-9-]+$"],
      i.is_map ? [] : ["${i.file}: not valid YAML, or not a mapping"],
      !i.is_map ? [] : (
        length(setsubtract(i.top_keys, local.infra_top_keys)) > 0 || !contains(i.top_keys, "oidc")
        ? ["${i.file}: top-level keys must be exactly: ${join(", ", local.infra_top_keys)} (found: ${join(", ", i.top_keys)})"] : []
      ),
      !i.is_map || !contains(i.top_keys, "oidc") ? [] : (
        !i.oidc_is_map ? ["${i.file}: oidc must be a mapping"] : concat(
          length(setsubtract(i.oidc_keys, local.infra_oidc_keys)) > 0
          ? ["${i.file}: unknown oidc key(s) ${join(", ", setsubtract(i.oidc_keys, local.infra_oidc_keys))}; allowed: ${join(", ", local.infra_oidc_keys)}"] : [],
          length(i.callbacks) > 0 && alltrue([for c in i.callbacks : try(length(trimspace(tostring(c))) > 0, false)])
          ? [] : ["${i.file}: oidc.callback must be a non-empty string or a list of non-empty strings"],
          length(i.groups) > 0 && alltrue([for g in i.groups : try(contains(keys(local.groups), g), false)])
          ? [] : ["${i.file}: oidc.groups must be a non-empty list of: ${join(", ", keys(local.groups))}"],
          try(regex("^.{1,50}$", i.name) != "", false)
          ? [] : ["${i.file}: oidc.name must be a string of 1 to 50 characters"],
          !i.has_pub || i.public == true || i.public == false ? [] : ["${i.file}: oidc.public must be true or false"],
        )
      ),
    )
  ])

  # Files that passed, as clients. Anything else is in infra_file_problems.
  infra_apps = [
    for i in local.infra_typed : {
      app       = i.app
      file      = i.file
      key       = upper(replace(i.app, "-", "_"))
      name      = i.name
      callbacks = i.callbacks
      groups    = i.groups
      public    = i.public
    } if length([for p in local.infra_file_problems : p if startswith(p, "${i.file}:")]) == 0
  ]

  infra_app_names         = [for i in local.infra_typed : i.app]
  infra_app_keys          = [for a in local.infra_apps : a.key]
  infra_hand_written_keys = [for k in keys(local.clients) : upper(replace(k, "-", "_"))]

  infra_problems = concat(
    local.infra_file_problems,
    length(local.infra_app_names) == length(distinct(local.infra_app_names)) ? [] : [
      "two infra.yaml files belong to apps with the same directory name (each name is one client and one Doppler key): ${join(", ", [for i in local.infra_typed : i.file if length([for j in local.infra_typed : j if j.app == i.app]) > 1])}"
    ],
    length(setintersection(local.infra_app_keys, local.infra_hand_written_keys)) == 0 ? [] : [
      "claims a client that pocketid.tf already writes by hand: ${join(", ", [for a in local.infra_apps : a.file if contains(local.infra_hand_written_keys, a.key)])}"
    ],
  )

  # One entry per app (duplicates are an error above; the first is kept so
  # the other checks still run).
  infra_by_app       = { for a in local.infra_apps : a.app => a... }
  infra_oidc_clients = { for app, list in local.infra_by_app : app => list[0] }
}

# Plans fail here. A resource's own precondition would not run for an app
# filtered out of its for_each, so the checks sit on this always-present object.
resource "terraform_data" "infra_checks" {
  lifecycle {
    precondition {
      condition     = length(local.infra_problems) == 0
      error_message = "infra.yaml problems: ${join("; ", local.infra_problems)}"
    }
  }
}

# Flipping public <-> confidential replaces the client: pocket-id makes a
# secret only when it creates the client (or on a rotation), and an in-place
# update to confidential would leave client_secret null. A replace is a
# destroy, so CI holds it for approval; the app gets a new client id and
# secret in Doppler.
resource "terraform_data" "infra_mode" {
  for_each = local.infra_oidc_clients

  input = each.value.public
}

resource "pocketid_client" "infra" {
  for_each = local.infra_oidc_clients

  name                = each.value.name
  callback_urls       = each.value.callbacks
  is_public           = each.value.public
  pkce_enabled        = true
  allowed_user_groups = [for g in each.value.groups : pocketid_group.this[g].id]

  # No prevent_destroy on purpose: deleting infra.yaml removes the client, and
  # CI's destroy gate holds that apply for approval.
  lifecycle {
    replace_triggered_by = [terraform_data.infra_mode[each.key]]
  }
}

# Read by the app's ExternalSecret on the doppler-ci store.
resource "doppler_secret" "infra_client" {
  for_each = { for app, a in local.infra_oidc_clients : app => a if !a.public }

  provider = doppler.k8s_at_home_min_ci

  project = "k8s-at-home"
  config  = "min-ci"
  name    = "${each.value.key}_POCKETID_CLIENT"
  value = jsonencode({
    client_id     = pocketid_client.infra[each.key].id
    client_secret = pocketid_client.infra[each.key].client_secret
  })

  # pocket-id returns a secret only when it creates the client: an imported
  # client, or one that became confidential in place, has none. Never write
  # that over a live Doppler value.
  lifecycle {
    precondition {
      condition = (
        try(length(pocketid_client.infra[each.key].id) > 0, false) &&
        try(length(pocketid_client.infra[each.key].client_secret) > 0, false)
      )
      error_message = "pocket-id has no client secret for ${each.key} (it only returns one when it creates the client). Not writing it to Doppler; replace the client (see README.md)."
    }
  }
}
