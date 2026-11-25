# The weekly Doppler export's tokens (cluster-apps/mini/security/doppler-export):
# one read token per config, all in one JSON secret in tf-at-home/export.
# A new config joins the export by existing in doppler.tf.
#
# They read tf-at-home/prd, which holds this stack's credentials, so they get a
# config of their own that no CI token reads, and its store token is never kept
# in a config CI reads. The job's own ClusterSecretStore reads it with a token
# the cluster bootstrap task makes.
#
# A config with no secrets yet must be in the job's ALLOW_EMPTY_CONFIGS, which
# treats any other empty config as wiped.
locals {
  doppler_export_config = "tf-at-home/export"

  # Every config except the export's own, which this file regenerates.
  doppler_exported_configs = setsubtract(local.doppler_config_keys, [local.doppler_export_config])
}

resource "doppler_service_token" "export" {
  for_each = local.doppler_exported_configs

  project = local.doppler_config_ref[each.key].project
  config  = local.doppler_config_ref[each.key].name
  name    = "export-read"
  access  = "read"

  lifecycle {
    # Every argument forces a new token: have it in Doppler before the old one
    # is revoked.
    create_before_destroy = true
  }
}

# "project/config" -> token, the shape the job reads.
resource "doppler_secret" "export_tokens" {
  project = local.doppler_config_ref[local.doppler_export_config].project
  config  = local.doppler_config_ref[local.doppler_export_config].name
  name    = "DOPPLER_EXPORT_TOKENS"
  value   = jsonencode({ for k, t in doppler_service_token.export : k => t.key })
}
