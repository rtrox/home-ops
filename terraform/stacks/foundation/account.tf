data "cloudflare_accounts" "rtrox" {
  name = "rtrox"
}

data "cloudflare_api_token_permission_groups_list" "all" {}

locals {
  account_id = data.cloudflare_accounts.rtrox.result[0].id

  # Permission group name -> ID, for every group a token here uses. A renamed
  # group comes back null, which each token's precondition catches.
  permission_group_ids = {
    for name in distinct(concat(
      flatten(values(local.r2_state_tokens)),
      flatten(values(local.ci_readonly_permissions)),
      local.dns_token_permissions,
      flatten(values(local.mini_token_permissions)),
      local.mini_cluster_token_permissions,
      local.r2_state_copy_permissions,
      local.truenas_token_permissions,
      local.truenas_acme_token_permissions,
    )) :
    name => one([for g in data.cloudflare_api_token_permission_groups_list.all.result : g.id if g.name == name])
  }
}
