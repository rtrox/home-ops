# pocket-id (auth.rtrox.io, running on mini): its groups and OIDC clients.
# Moved from terraform-record's pocketid stack in migration P2-4. Users
# aren't managed here yet.
#
# Only public clients (PKCE, no secret) are left here. A confidential client
# belongs in its app's infra.yaml (infra.tf), which writes its secret to
# Doppler. Never add one here: pocket-id returns a secret only when it creates
# the client, so an imported one has none in state (README.md, "Moving a
# client from pocketid.tf to infra.yaml").
#
# Clients an app declares itself (infra.yaml) are in infra.tf.
#
# Renaming a group or client, or changing a callback URL, changes it in
# pocket-id and can break that app's login.

locals {
  # Group name -> friendly name.
  groups = {
    admins = "Admins"
    family = "Family Members"
  }

  # Key: the app. name: pocket-id's display name. groups: the groups allowed
  # to use the client.
  clients = {
    # A public client: PKCE, no secret.
    booklore = {
      name          = "Booklore"
      callback_urls = ["https://booklore.rtrox.io/oauth2-callback"]
      is_public     = true
      groups        = ["family"]
    }
    # A public client: the browser does the code exchange (PKCE, no secret).
    # curt runs on Cloudflare Workers, not in mini, and gives admins its admin
    # rights.
    curt = {
      name          = "curt"
      callback_urls = ["https://app.trx.fm/auth/callback"]
      is_public     = true
      groups        = ["family"]
    }
  }
}

resource "pocketid_group" "this" {
  for_each = local.groups

  name          = each.key
  friendly_name = each.value

  # No prevent_destroy: CI holds any apply that destroys for approval. Deleting
  # a group drops it from every client and user that uses it.
}

resource "pocketid_client" "this" {
  for_each = local.clients

  name          = each.value.name
  callback_urls = each.value.callback_urls
  is_public     = each.value.is_public
  pkce_enabled  = true

  allowed_user_groups = [for g in each.value.groups : pocketid_group.this[g].id]

  # No prevent_destroy: CI holds any apply that destroys for approval. A deleted
  # client takes its ID and secret with it: the app's login breaks until a new
  # client's values are in Doppler and the app.
}
