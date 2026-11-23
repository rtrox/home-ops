# Migration phase 2 (P2-1): what this stack adopts, as it existed on
# 2026-11-22. The Doppler structure was made by hand; the bucket and the
# doppler_secrets come from terraform-record's cloudflare stack, which forgets
# them (removed, destroy = false) before this stack is applied. See
# MIGRATION.md. Delete this file in the cleanup PR once the zero-diff gate
# passes.
#
# Imports by value don't apply here: every object below is read back in full.
# The Cloudflare tokens are rotated instead (new ones in this stack), since
# their value exists only in the create response.
locals {
  imported_projects = ["chezmoi-secrets", "hosts-at-home", "k8s-at-home", "tf-at-home"]
  imported_environments = [
    "chezmoi-secrets/dot",
    "chezmoi-secrets/dsk",
    "hosts-at-home/prd",
    "hosts-at-home/ci",
    "k8s-at-home/min",
    "tf-at-home/prd",
    "tf-at-home/ci",
  ]
  imported_configs = [
    "chezmoi-secrets/dot",
    "chezmoi-secrets/dot_desktop",
    "chezmoi-secrets/dot_laptop",
    "chezmoi-secrets/dot_wrk",
    "chezmoi-secrets/dsk",
    "hosts-at-home/prd",
    "hosts-at-home/ci",
    "k8s-at-home/min",
    "tf-at-home/prd",
    "tf-at-home/ci",
    # Created by this stack's doppler_environment, but Doppler makes an
    # environment's root config itself, and the provider's create call is
    # refused on the free plan ("no access to config inheritance"). So the
    # root config is imported, like the others.
    "tf-at-home/ci-apply",
  ]
  # The hand-made secrets holding the hand-made write tokens. Imported, then
  # updated to the new tokens, so the stacks that read them by name pick the
  # new tokens up unchanged.
  imported_write_tokens = [
    "hosts-at-home/prd",
    "k8s-at-home/min",
    "tf-at-home/prd",
    "tf-at-home/ci",
  ]
}

import {
  to = cloudflare_r2_bucket.tofu_state
  id = "${local.account_id}/tofu-state/default"
}

import {
  for_each = toset(local.imported_projects)
  to       = doppler_project.this[each.key]
  id       = each.key
}

import {
  for_each = toset(local.imported_environments)
  to       = doppler_environment.this[each.key]
  id       = replace(each.key, "/", ".")
}

import {
  for_each = toset(local.imported_configs)
  to       = doppler_config.this[each.key]
  id       = "${local.doppler_configs[each.key].project}.${local.doppler_configs[each.key].environment}.${local.doppler_configs[each.key].name}"
}

import {
  for_each = toset(local.imported_write_tokens)
  to       = doppler_secret.write_token[each.key]
  id       = "tf-at-home.prd.${local.doppler_write_tokens[each.key]}"
}

# From terraform-record cloudflare (r2_state.tf, ci_readonly.tf), with the
# same addresses.
import {
  for_each = local.r2_state_tokens
  to       = doppler_secret.r2_state[each.key]
  id       = "tf-at-home.prd.R2_STATE_${upper(each.key)}"
}

import {
  to = doppler_secret.ci_cloudflare_token
  id = "tf-at-home.ci.CLOUDFLARE_TERRAFORM_TOKEN"
}

import {
  to = doppler_secret.ci_r2_state_readonly
  id = "tf-at-home.ci.R2_STATE_READONLY"
}

# P2-1b: the two home-ops GitHub Environments as made by hand (read with the
# API on 2026-11-22), and each one's single branch policy (`main`). The values
# are the policies' API IDs.
locals {
  imported_github_environment_policies = {
    "tofu-apply-gated" = 67820985
    "tofu-apply"       = 67821039
  }
}

import {
  for_each = local.github_environments
  to       = github_repository_environment.this[each.key]
  id       = "${local.github_repository}:${each.key}"
}

import {
  for_each = local.imported_github_environment_policies
  to       = github_repository_environment_deployment_policy.main[each.key]
  id       = "${local.github_repository}:${each.key}:${each.value}"
}

# P2-3: mini's backup buckets and their Doppler secrets, from terraform-record's
# backblaze and cloudflare stacks, which forget them first (removed, destroy =
# false). The keys and the R2 token are new (backups.tf); the secrets are
# imported and updated to them. The bucket IDs come from a lookup by name, so
# these can only adopt a bucket that exists: a missing one fails the plan.
locals {
  imported_mini_backup_buckets = {
    tofu_state_history  = "rtrox-tofu-state-history"
    mini_secrets_backup = "k8s-mini-rtrox-io-secrets-backup"
  }
}

data "b2_bucket" "imported" {
  for_each    = local.imported_mini_backup_buckets
  bucket_name = each.value
}

import {
  to = module.tofu_state_history.b2_bucket.this
  id = data.b2_bucket.imported["tofu_state_history"].bucket_id
}

import {
  to = module.mini_secrets_backup.b2_bucket.this
  id = data.b2_bucket.imported["mini_secrets_backup"].bucket_id
}

import {
  to = doppler_secret.tofu_state_r2_source
  id = "k8s-at-home.min.TOFU_STATE_R2_SOURCE"
}

import {
  to = doppler_secret.tofu_state_history_bucket
  id = "k8s-at-home.min.TOFU_STATE_HISTORY_BACKBLAZE_BUCKET"
}

import {
  to = doppler_secret.mini_secrets_backup_bucket
  id = "k8s-at-home.min.SECRETS_BACKUP_BACKBLAZE_BUCKET"
}
