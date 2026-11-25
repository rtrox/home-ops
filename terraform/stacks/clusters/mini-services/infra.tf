# OIDC clients declared by the apps themselves: every
# cluster-apps/mini/<namespace>/<app>/infra.yaml with an `oidc` key (see
# README.md). Separate from pocketid_client.this, which holds the hand-written
# clients above and can't be destroyed: these have no prevent_destroy, so
# deleting an infra.yaml destroys its client. CI holds such an apply for the
# owner's approval (it destroys), which is the only guard.
#
# Each confidential client's id and secret go to k8s-at-home/min-ci as
# <APP>_POCKETID_CLIENT, the same JSON shape the hand-made secrets use.
# Public clients have no secret, so they get no Doppler entry.

locals {
  infra_root = "${path.module}/../../../../cluster-apps/mini"

  # [{app, file, oidc}] for every infra.yaml that has an `oidc` key. The app is
  # the directory name; a file that isn't valid YAML fails the plan.
  infra_oidc = [
    for f in sort(tolist(fileset(local.infra_root, "*/*/infra.yaml"))) : {
      app  = basename(dirname(f))
      file = "cluster-apps/mini/${f}"
      oidc = try(yamldecode(file("${local.infra_root}/${f}")).oidc, null)
    } if try(yamldecode(file("${local.infra_root}/${f}")).oidc, null) != null
  ]

  # callback may be one URL or a list. Doppler key: the app name upper-cased,
  # - to _ (grafana-oss -> GRAFANA_OSS_POCKETID_CLIENT).
  infra_apps = [
    for i in local.infra_oidc : {
      app       = i.app
      file      = i.file
      key       = upper(replace(i.app, "-", "_"))
      name      = try(i.oidc.name, i.app)
      callbacks = try(tolist(i.oidc.callback), try([tostring(i.oidc.callback)], []))
      groups    = try(tolist(i.oidc.groups), [])
      public    = try(tobool(i.oidc.public), false)
    }
  ]

  # One entry per app; a duplicate app name keeps its first and is reported by
  # the precondition below.
  infra_clients = { for a in local.infra_apps : a.app => a... }
  infra_oidc_clients = {
    for app, list in local.infra_clients : app => list[0]
  }

  infra_hand_written_keys = [for k in keys(local.clients) : upper(replace(k, "-", "_"))]
  infra_app_names         = [for a in local.infra_apps : a.app]
  infra_app_keys          = [for a in local.infra_apps : a.key]
}

# Plans fail here, with a message naming the file, instead of deep inside a
# resource. A resource's precondition would not run for an app that is
# filtered out of its for_each, so the checks live on this one always-present
# object.
resource "terraform_data" "infra_checks" {
  lifecycle {
    precondition {
      condition     = length(local.infra_app_names) == length(distinct(local.infra_app_names))
      error_message = "Two infra.yaml files with an oidc key belong to apps with the same directory name. Each app name is one client and one Doppler key; rename one."
    }

    precondition {
      condition     = length(local.infra_app_keys) == length(distinct(local.infra_app_keys))
      error_message = "Two infra.yaml files map to the same Doppler key (the app name upper-cased, - becoming _): e.g. foo-bar and foo_bar. Rename one."
    }

    precondition {
      condition     = length(setintersection(local.infra_app_keys, local.infra_hand_written_keys)) == 0
      error_message = "An infra.yaml claims a client that pocketid.tf already writes by hand. Remove one of them: ${join(", ", [for a in local.infra_apps : a.file if contains(local.infra_hand_written_keys, a.key)])}."
    }

    precondition {
      condition     = alltrue([for a in local.infra_apps : length(a.callbacks) > 0])
      error_message = "An infra.yaml oidc block has no callback (a URL, or a list of them): ${join(", ", [for a in local.infra_apps : a.file if length(a.callbacks) == 0])}."
    }

    precondition {
      condition     = alltrue([for a in local.infra_apps : length(a.groups) > 0])
      error_message = "An infra.yaml oidc block has no groups (a client with none would admit every user): ${join(", ", [for a in local.infra_apps : a.file if length(a.groups) == 0])}."
    }

    precondition {
      condition     = alltrue([for a in local.infra_apps : alltrue([for g in a.groups : contains(keys(local.groups), g)])])
      error_message = "An infra.yaml oidc block names a group that isn't in local.groups (${join(", ", keys(local.groups))}): ${join(", ", [for a in local.infra_apps : a.file if !alltrue([for g in a.groups : contains(keys(local.groups), g)])])}."
    }
  }
}

resource "pocketid_client" "infra" {
  for_each = local.infra_oidc_clients

  name          = each.value.name
  callback_urls = each.value.callbacks
  is_public     = each.value.public
  pkce_enabled  = true

  allowed_user_groups = compact([for g in each.value.groups : try(pocketid_group.this[g].id, "")])

  # No prevent_destroy on purpose: deleting infra.yaml removes the client, and
  # CI's destroy gate holds that apply for approval.
}

# Read by the app's ExternalSecret on the doppler-ci store.
resource "doppler_secret" "infra_client" {
  for_each = { for app, a in local.infra_oidc_clients : app => a if !a.public }

  provider = doppler.k8s_at_home_min_ci

  project = "k8s-at-home"
  config  = "min-ci"
  name    = "${each.value.key}_POCKETID_CLIENT"
  value = jsonencode({
    client_id     = pocketid_client.infra[each.key].client_id
    client_secret = pocketid_client.infra[each.key].client_secret
  })
}
