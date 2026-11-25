# The Doppler config k8s-at-home/min-ci: the secrets written by stacks CI
# plans (clusters/mini/README.md). A read token on `min` would read every app's
# secrets, and every PR plan job holds the ci token, so those stacks write
# here instead. foundation keeps writing its own mini secrets to `min`.
#
# One token per consumer, all under the key name _provider_env.json names
# (local.doppler_write_tokens["k8s-at-home/min-ci"]): the laptop's read/write
# token is made in doppler.tf with the other write tokens, the other two here.
# No token for `min` goes into ci or ci-apply.
locals {
  min_ci_token_key = local.doppler_write_tokens["k8s-at-home/min-ci"]
}

# PR plan jobs (tf-at-home/ci): read-only.
resource "doppler_service_token" "min_ci_plan" {
  project = local.doppler_config_ref["k8s-at-home/min-ci"].project
  config  = local.doppler_config_ref["k8s-at-home/min-ci"].name
  name    = "ci-plan-read"
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_min_ci_token" {
  project = "tf-at-home"
  config  = "ci"
  name    = local.min_ci_token_key
  value   = doppler_service_token.min_ci_plan.key
}

# Apply jobs (tf-at-home/ci-apply): read/write.
resource "doppler_service_token" "min_ci_apply" {
  project = local.doppler_config_ref["k8s-at-home/min-ci"].project
  config  = local.doppler_config_ref["k8s-at-home/min-ci"].name
  name    = "ci-apply-write"
  access  = "read/write"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "ci_apply_min_ci_token" {
  project = "tf-at-home"
  config  = doppler_config.this["tf-at-home/ci-apply"].name
  name    = local.min_ci_token_key
  value   = doppler_service_token.min_ci_apply.key
}

# The cluster's read-only token for min-ci, as a plain-string key in
# k8s-at-home/min: ESO's Doppler provider ignores remoteRef.property, so a
# JSON value could not be split. An ExternalSecret on the existing `doppler`
# store renders it into the new store's Secret.
resource "doppler_service_token" "min_ci_cluster" {
  project = local.doppler_config_ref["k8s-at-home/min-ci"].project
  config  = local.doppler_config_ref["k8s-at-home/min-ci"].name
  name    = "mini-cluster-read"
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}

resource "doppler_secret" "mini_ci_cluster_token" {
  project = "k8s-at-home"
  config  = "min"
  name    = "DOPPLER_CI_STORE_TOKEN"
  value   = doppler_service_token.min_ci_cluster.key
}
