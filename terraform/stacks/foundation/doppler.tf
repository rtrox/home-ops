# Every Doppler project, environment and config, and one write token per
# config Terraform writes to. A new cluster or site is a list entry here (and,
# if Terraform writes to it, one in terramate.tm.hcl's doppler_write_tokens),
# not clicks.
#
# Every write here uses the default provider, the owner's personal token
# (task tf:* sets DOPPLER_TOKEN). The free plan has no service accounts, and
# only a personal token can create service tokens. It also means this stack
# never depends on the write tokens it mints.
#
# Project names stay as they are until phase 3 renames them.
locals {
  # project -> description and environments. An environment's root config has
  # the environment's slug as its name; branch configs are listed under it.
  doppler_projects = {
    "chezmoi-secrets" = {
      description = "Secrets for use in dotfiles"
      environments = {
        dot = { name = "Dotfiles - Main", branches = ["dot_desktop", "dot_laptop", "dot_wrk"] }
        dsk = { name = "Desktop" }
      }
    }
    "hosts-at-home" = {
      description = "Secrets for non-Kubernetes hosts (NAS, Pis, Proxmox). Terraform writes some here; some are added to hosts by hand."
      environments = {
        prd = { name = "HL15" }
        ci  = { name = "Continuous Integration" }
      }
    }
    "k8s-at-home" = {
      description = ""
      environments = {
        min = { name = "Mini" }
      }
    }
    "tf-at-home" = {
      description = ""
      environments = {
        prd = { name = "Production" }
        ci  = { name = "Continuous Integration" }
        # CI's apply credentials (ci_apply.tf). Its own root config, so the ci
        # and prd tokens can't read it.
        ci-apply = { name = "CI Apply" }
      }
    }
  }

  # "project/environment" -> environment.
  doppler_environments = merge([
    for project, p in local.doppler_projects : {
      for slug, env in p.environments : "${project}/${slug}" => {
        project = project
        slug    = slug
        name    = env.name
      }
    }
  ]...)

  # "project/config" -> config: each environment's root config, then its
  # branch configs.
  doppler_configs = merge([
    for project, p in local.doppler_projects : merge([
      for slug, env in p.environments : {
        for config in concat([slug], try(env.branches, [])) : "${project}/${config}" => {
          project     = project
          environment = slug
          name        = config
        }
      }
    ]...)
  ]...)
}

resource "doppler_project" "this" {
  for_each = local.doppler_projects

  name        = each.key
  description = each.value.description

  lifecycle {
    prevent_destroy = true
  }
}

resource "doppler_environment" "this" {
  for_each = local.doppler_environments

  project = doppler_project.this[each.value.project].name
  slug    = each.value.slug
  name    = each.value.name

  lifecycle {
    prevent_destroy = true
  }
}

# Root configs (name == environment): Doppler creates one with every
# environment, so every root config here was imported (P2-1), never
# created. The provider's create would try to set inheritance, which the free
# plan refuses.
resource "doppler_config" "this" {
  for_each = local.doppler_configs

  project     = doppler_environment.this["${each.value.project}/${each.value.environment}"].project
  environment = doppler_environment.this["${each.value.project}/${each.value.environment}"].slug
  name        = each.value.name

  lifecycle {
    prevent_destroy = true
  }
}

# One read/write token per config Terraform writes to, kept in tf-at-home/prd
# under the name the stacks read (local.doppler_write_tokens, generated from
# terramate.tm.hcl). Named for the consumer: the Terraform stacks, which read it
# through tf-at-home/prd.
resource "doppler_service_token" "write" {
  for_each = local.doppler_write_tokens

  project = doppler_config.this[each.key].project
  config  = doppler_config.this[each.key].name
  name    = "tf-stacks-write"
  access  = "read/write"

  lifecycle {
    # Every argument forces a new token: have it in Doppler before the old one
    # is revoked.
    create_before_destroy = true
  }
}

resource "doppler_secret" "write_token" {
  for_each = local.doppler_write_tokens

  project = "tf-at-home"
  config  = "prd"
  name    = each.value
  value   = doppler_service_token.write[each.key].key
}
