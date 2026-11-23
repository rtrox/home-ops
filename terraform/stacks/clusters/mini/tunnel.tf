# Mini's Cloudflare Tunnel: envoy-external's way in from the internet
# (cluster-apps/mini/network/cloudflared). Locally managed: its ingress rules
# are in the cloudflared config there, not here.
#
# A new tunnel, not terraform-record's (migration P2-3): its secret is new
# too, so no secret had to be imported by value. cloudflared picks it up from
# CLOUDFLARED_CREDENTIALS, and external-dns points min-ext.rtrox.io at it
# through the tunnel's DNSEndpoint (TUNNEL_ENDPOINT). terraform-record deletes
# the old tunnel once cloudflared runs on this one.
#
# Neither the tunnel nor its secret may be destroyed by an apply: a new tunnel
# has a new ID (min-ext.rtrox.io's CNAME target), and a new secret cuts
# cloudflared off until it restarts with it.
resource "random_bytes" "tunnel_secret" {
  length = 32

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "mini" {
  account_id    = local.account_id
  name          = "mini-external-ingress"
  config_src    = "local"
  tunnel_secret = random_bytes.tunnel_secret.base64

  lifecycle {
    prevent_destroy = true
    # Cloudflare never returns the secret, so the state only has what was
    # sent. A change here would be a rotation, which is its own procedure.
    ignore_changes = [tunnel_secret]
  }
}

# Read by cluster-apps/mini/network/cloudflared: the app's ExternalSecret
# builds TUNNEL_TOKEN from it, the config's builds TUNNEL_ENDPOINT. The same
# keys as terraform-record wrote; the import takes over the Doppler secret and
# updates it to this tunnel.
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
