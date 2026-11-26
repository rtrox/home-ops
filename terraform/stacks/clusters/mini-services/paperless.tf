# Paperless's Django SECRET_KEY (sessions, signed links), generated here and
# read by its ExternalSecret from k8s-at-home/min-ci. It used to be the OIDC
# client secret; split out when the client moved to infra.yaml.
#
# Rotating it logs everyone out:
#   task tf:apply STACK=clusters/mini-services -- -replace=random_password.paperless_secret_key
resource "random_password" "paperless_secret_key" {
  length  = 64
  special = false

  lifecycle {
    ignore_changes = all
  }
}

resource "doppler_secret" "paperless_secret_key" {
  provider = doppler.k8s_at_home_min_ci

  project = "k8s-at-home"
  config  = "min-ci"
  name    = "PAPERLESS_SECRET_KEY"
  value   = random_password.paperless_secret_key.result
}
