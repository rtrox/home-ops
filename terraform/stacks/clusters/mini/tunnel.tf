# Mini's Cloudflare Tunnel: envoy-external's way in from the internet
# (cluster-apps/mini/network/cloudflared). Locally managed: its ingress rules
# are in the cloudflared config there, not here.
#
# The tunnel secret must never change by accident: a new one cuts every
# external hostname off until cloudflared restarts with it. So it is a
# random_bytes that can't be replaced (prevent_destroy) or changed in place
# (ignore_changes), the tunnel ignores its own copy of the secret, and the
# tunnel can't be destroyed either (a new tunnel has a new ID, which every
# external-dns CNAME points at). Rotating it on purpose is a procedure of its
# own: new secret, then the tunnel, then cloudflared.
#
# random_bytes rather than terraform-record's random_id: random_id's `id` is
# the secret itself (base64url) and isn't marked sensitive, so every plan
# printed it ("Refreshing state... [id=...]"). random_bytes keeps it in
# `base64`, which is sensitive, and has no id. Imported by value from the same
# bytes (imports.tf), so nothing changes.
resource "random_bytes" "tunnel_secret" {
  length = 35

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all

    # P2-3 move only (delete with imports.tf): adopted by value, so a plan
    # without the value would create a new secret instead of importing it.
    precondition {
      condition     = var.import_tunnel_secret != null
      error_message = "TF_VAR_import_tunnel_secret is not set. Until the cleanup PR, every plan of this stack must supply it (MIGRATION.md, \"By-value imports\"); without it the plan would make a new tunnel secret."
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "mini" {
  account_id    = local.account_id
  name          = "mini_external_ingress"
  tunnel_secret = random_bytes.tunnel_secret.base64

  lifecycle {
    prevent_destroy = true
    # Cloudflare never returns the secret, so the imported tunnel has none in
    # state; a write would change it. config_src is read back from the API
    # (local) and never set here: setting it replaces the tunnel.
    ignore_changes = [tunnel_secret, config_src]
  }
}

# Read by cluster-apps/mini/network/cloudflared: the app's ExternalSecret
# builds TUNNEL_TOKEN from it, the config's builds TUNNEL_ENDPOINT. Same keys
# and values as terraform-record wrote, so the import changes nothing.
resource "doppler_secret" "cloudflared_credentials" {
  provider = doppler.k8s_at_home_min

  project = "k8s-at-home"
  config  = "min"
  name    = "CLOUDFLARED_CREDENTIALS"
  value = jsonencode({
    AccountTag   = local.account_id
    TunnelName   = cloudflare_zero_trust_tunnel_cloudflared.mini.name
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.mini.id
    TunnelSecret = random_bytes.tunnel_secret.base64
  })
}
