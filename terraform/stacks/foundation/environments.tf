# The two GitHub Environments the terraform-apply workflow's jobs run in, and
# the secret each holds. Only this slice of GitHub is managed here; repo
# settings, the ruleset and the runner App stay hand-made until phase 7.
#
# The provider reads GITHUB_TOKEN (a fine-grained PAT, home-ops only, in
# tf-at-home/prd as GITHUB_TERRAFORM_TOKEN; see _provider_env.json).
locals {
  github_repository = "home-ops"

  # The owner's numeric GitHub user ID (public, from the users API): the
  # required reviewer of tofu-apply-gated.
  github_reviewer_user_id = 5419724

  # tofu-apply-gated waits for the owner's approval; tofu-apply runs at once.
  # Both only deploy from main. Matches the Environments as made by hand.
  github_environments = {
    "tofu-apply-gated" = { reviewers = [local.github_reviewer_user_id] }
    "tofu-apply"       = { reviewers = [] }
  }
}

resource "github_repository_environment" "this" {
  for_each = local.github_environments

  repository          = local.github_repository
  environment         = each.key
  can_admins_bypass   = true
  prevent_self_review = false

  dynamic "reviewers" {
    for_each = length(each.value.reviewers) > 0 ? [1] : []
    content {
      users = each.value.reviewers
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  for_each = local.github_environments

  repository     = local.github_repository
  environment    = github_repository_environment.this[each.key].environment
  branch_pattern = "main"
}

# Both Environments hold the same secret, never a repo secret: the apply jobs
# read tf-at-home/ci-apply with it (terraform-apply.yaml).
resource "github_actions_environment_secret" "ci_doppler_tf_apply" {
  for_each = local.github_environments

  repository  = local.github_repository
  environment = github_repository_environment.this[each.key].environment
  secret_name = "CI_DOPPLER_TF_APPLY"
  value       = doppler_service_token.ci_apply_read.key
}
