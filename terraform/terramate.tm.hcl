# Stack tags (`tags = [...]` in stack.tm.hcl) the CI workflows honour:
#   laptop-only  CI never plans, applies or drift-checks it (it needs the
#                owner's personal Doppler token); PRs just say to use the laptop.
#   ci-skip      CI never plans, applies or drift-checks it either, but unlike
#                laptop-only it keeps the shared state passphrase: for a stack
#                CI can't plan yet (e.g. while it moves in, before CI has its
#                credentials). Dropping the tag later needs no re-encryption.
#   ci-apply     opt-in: terraform-apply.yaml applies it on merge to main.
#                Approval is dynamic, not a tag: a plan with any destroy,
#                replace or forget waits in `tofu-apply-gated`, any other
#                applies at once in `tofu-apply`.
#
# State: one R2 bucket, one key per stack. The endpoint and credentials are NOT
# here: they come from Doppler (R2_STATE_READWRITE) as AWS_ENDPOINT_URL_S3,
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, set by task tf:*.
globals "backend" {
  bucket = "tofu-state"
  region = "auto"
}

generate_hcl "_backend.tf" {
  content {
    terraform {
      # OpenTofu; the exact version is pinned in .mise.toml.
      required_version = "~> 1.13"

      backend "s3" {
        bucket       = global.backend.bucket
        key          = "${tm_trimprefix(terramate.stack.path.absolute, "/terraform/")}/terraform.tfstate"
        region       = global.backend.region
        use_lockfile = true

        # R2 speaks S3 but isn't AWS: skip the AWS-only checks.
        use_path_style              = true
        skip_credentials_validation = true
        skip_region_validation      = true
        skip_requesting_account_id  = true
        skip_metadata_api_check     = true
        skip_s3_checksum            = true
      }

      # Every stack's state and plans are encrypted. The passphrase comes from
      # Doppler (TOFU_STATE_PASSPHRASE) as TF_VAR_state_passphrase.
      encryption {
        key_provider "pbkdf2" "main" {
          passphrase = var.state_passphrase
        }
        method "aes_gcm" "main" {
          keys = key_provider.pbkdf2.main
        }
        state {
          method   = method.aes_gcm.main
          enforced = true
        }
        plan {
          method   = method.aes_gcm.main
          enforced = true
        }
      }
    }

    variable "state_passphrase" {
      type      = string
      sensitive = true
    }
  }
}

# Providers. Each stack lists what it needs in its stack.tm.hcl globals
# (providers, doppler_writes, secret_vars); these are the defaults and lookup
# tables. Versions are NOT generated: each stack pins them in its own
# versions.tf, so Renovate's terraform manager can bump them and their lock
# files.
#
# Credentials never go through a `data "doppler_secrets"` source: a data source
# is stored in state, which would put a whole Doppler config in every stack's
# state (and CI's plan job can decrypt state). Instead the wrapper (task
# tf:*) and CI read just the keys listed in the generated _provider_env.json
# and export them as environment variables: each provider's standard one, or
# TF_VAR_<name> for the sensitive variables below.
globals {
  providers      = []
  doppler_writes = []

  # Extra secrets a stack reads, as sensitive variables. Name -> where it lives:
  #   secret_vars = { cloudflare_user_id = { project = "tf-at-home", key = "CLOUDFLARE_USER_ID" } }
  # generates `variable "cloudflare_user_id"` and exports TF_VAR_cloudflare_user_id.
  # Only the keys named here are read. Unless the stack is laptop-only, CI
  # needs them in its `ci` (and `ci-apply`) config.
  secret_vars = {}

  # Per-stack credential keys: provider name -> the Doppler key to read instead
  # of that provider's default in provider_env, so a stack gets its own scoped
  # token rather than the shared one:
  #   provider_keys = { cloudflare = "CLOUDFLARE_DNS_TOKEN" }
  # Only `key` is replaced; env and project stay, and a provider with several
  # provider_env rows gets the same key on each. Every name must be in the
  # stack's `providers` (asserted below), or it would silently fall back to the
  # shared key. The key must exist in tf-at-home/prd, tf-at-home/ci (a
  # read-only token; not needed for laptop-only stacks) and, for a ci-apply
  # stack, tf-at-home/ci-apply. Foundation creates these tokens.
  provider_keys = {}

  # Only the foundation stack sets this: it gets _doppler_write_tokens.tf.
  manages_doppler_write_tokens = false

  # Doppler config -> the tf-at-home secret holding its write token. (Renamed
  # with the Doppler projects after phase 4.)
  #
  # The foundation stack creates one read/write service token per entry and
  # writes it to that secret (in tf-at-home/prd), so a config Terraform writes
  # to is one line here. terraform-record's stacks read the same secret names
  # until they move.
  #
  # NOTE for CI: a stack with doppler_writes needs these same key names in
  # tf-at-home/ci (and ci-apply), holding tokens it can use; the proxmox stack
  # has none.
  doppler_write_tokens = {
    "hosts-at-home/prd"   = "DOPPLER_TRUENAS_WRITE_TOKEN"
    "k8s-at-home/min"     = "DOPPLER_MINI_WRITE_TOKEN"
    "k8s-at-home/min-ci"  = "DOPPLER_MINI_CI_WRITE_TOKEN"
    "tf-at-home/prd"      = "DOPPLER_TF_WRITE_TOKEN"
    "tf-at-home/ci"       = "DOPPLER_TF_CI_WRITE_TOKEN"
    "tf-at-home/ci-apply" = "DOPPLER_TF_CI_APPLY_WRITE_TOKEN"
  }

  # Provider -> the standard environment variable carrying its credential, and
  # the Doppler project/key it is read from (config: prd on the laptop, ci or
  # ci-apply in CI, selected by the token).
  provider_env = {
    # The B2 provider key `terraform-backblaze`, made by hand: every capability
    # except bypassGovernance, so it can't delete Object Locked files. Its two
    # rows mean provider_keys can't give a stack its own B2 key yet (it would
    # put the same Doppler key in both variables).
    backblaze = [
      { env = "B2_APPLICATION_KEY_ID", project = "tf-at-home", key = "BACKBLAZE_APPLICATION_KEY_ID" },
      { env = "B2_APPLICATION_KEY", project = "tf-at-home", key = "BACKBLAZE_APPLICATION_KEY" },
    ]
    cloudflare = [
      { env = "CLOUDFLARE_API_TOKEN", project = "tf-at-home", key = "CLOUDFLARE_TERRAFORM_TOKEN" },
    ]
    # A fine-grained PAT limited to home-ops (foundation only; laptop-only).
    github = [
      { env = "GITHUB_TOKEN", project = "tf-at-home", key = "GITHUB_TERRAFORM_TOKEN" },
    ]
    # A pocket-id API key, made by hand in pocket-id's admin UI. Its keys
    # have no scopes, so this is an admin key, and tf-at-home/ci holds one too
    # (the owner accepted that, so CI can plan clusters/mini-services).
    pocketid = [
      { env = "POCKETID_API_TOKEN", project = "tf-at-home", key = "POCKETID_API_TOKEN" },
    ]
    # The token is written to hosts-at-home by the Ansible proxmox role.
    proxmox = [
      { env = "PROXMOX_VE_API_TOKEN", project = "hosts-at-home", key = "PVE_TERRAFORM_API_TOKEN" },
    ]
  }

  # The GitHub account that owns the repositories the github provider manages.
  github_owner = "rtrox"

  pocketid_base_url = "https://auth.rtrox.io"

  proxmox_endpoint = "https://pve.rtrox.io:8006/"
}

assert {
  assertion = tm_alltrue([for p in tm_keys(global.provider_keys) : tm_contains(global.providers, p)])
  message   = "provider_keys names a provider that isn't in this stack's providers (typo?); it would be ignored and the shared key used."
}

# The credential mapping the laptop wrapper and CI read: [{env, project, key}].
generate_file "_provider_env.json" {
  content = "${tm_jsonencode(tm_concat(
    tm_flatten([for p in global.providers : [
      for r in global.provider_env[p] : tm_try(
        { env = r.env, project = r.project, key = global.provider_keys[p] },
        r,
      )
    ]]),
    [for d in global.doppler_writes : {
      env     = "TF_VAR_doppler_write_token_${tm_replace(tm_replace(d, "-", "_"), "/", "_")}"
      project = "tf-at-home"
      key     = global.doppler_write_tokens[d]
    }],
    [for n, v in global.secret_vars : {
      env     = "TF_VAR_${n}"
      project = v.project
      key     = v.key
    }],
  ))}\n"
}

generate_hcl "_providers.tf" {
  content {
    # Reads DOPPLER_TOKEN from the environment (the CLI token on the laptop,
    # a scoped service token in CI). Only used by stacks that write secrets.
    provider "doppler" {}

    # One alias per Doppler config the stack writes to, e.g. hosts-at-home/prd
    # becomes provider = doppler.hosts_at_home_prd. Its token is a sensitive
    # variable fed from the environment (see _provider_env.json).
    tm_dynamic "variable" {
      for_each = global.doppler_writes
      labels   = ["doppler_write_token_${tm_replace(tm_replace(variable.value, "-", "_"), "/", "_")}"]
      attributes = {
        type      = tm_hcl_expression("string")
        sensitive = true
      }
    }

    tm_dynamic "provider" {
      for_each = global.doppler_writes
      labels   = ["doppler"]
      attributes = {
        alias         = tm_replace(tm_replace(provider.value, "-", "_"), "/", "_")
        doppler_token = tm_hcl_expression("var.doppler_write_token_${tm_replace(tm_replace(provider.value, "-", "_"), "/", "_")}")
      }
    }

    tm_dynamic "variable" {
      for_each = global.secret_vars
      labels   = [variable.key]
      attributes = {
        type      = tm_hcl_expression("string")
        sensitive = true
      }
    }

    # The cloudflare provider reads CLOUDFLARE_API_TOKEN itself.
    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "cloudflare") ? [1] : []
      labels   = ["cloudflare"]
      content {}
    }

    # The github provider reads GITHUB_TOKEN itself.
    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "github") ? [1] : []
      labels   = ["github"]
      attributes = {
        owner = global.github_owner
      }
    }

    # The b2 provider (Backblaze/b2) reads B2_APPLICATION_KEY_ID and
    # B2_APPLICATION_KEY itself. A stack lists it as "backblaze".
    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "backblaze") ? [1] : []
      labels   = ["b2"]
      content {}
    }

    # The pocketid provider (pocket-id/pocketid) reads POCKETID_API_TOKEN itself.
    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "pocketid") ? [1] : []
      labels   = ["pocketid"]
      attributes = {
        base_url = global.pocketid_base_url
      }
    }

    # The proxmox provider reads PROXMOX_VE_API_TOKEN itself.
    tm_dynamic "provider" {
      for_each = tm_contains(global.providers, "proxmox") ? [1] : []
      labels   = ["proxmox"]
      attributes = {
        endpoint = global.proxmox_endpoint
      }
    }
  }
}

# The write-token table above, as a local, for the stack that creates the
# tokens (foundation). One list, so the providers other stacks generate and the
# tokens foundation creates can't drift apart.
generate_hcl "_doppler_write_tokens.tf" {
  condition = global.manages_doppler_write_tokens

  content {
    locals {
      doppler_write_tokens = global.doppler_write_tokens
    }
  }
}
