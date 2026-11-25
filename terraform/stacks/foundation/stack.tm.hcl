stack {
  name        = "foundation"
  description = "Doppler projects, environments, configs and write tokens; the R2 state bucket, its tokens and its B2 history; mini's secrets-backup bucket; the per-stack Cloudflare tokens, mini's external-dns and cert-manager tokens and the TrueNAS ACME tokens; CI's credentials; the GitHub Environments the apply workflow runs in"
  id          = "29e13f3f-ad14-43b1-9aab-c270f55b9b66"

  # Applied from the owner's laptop only. Its default Doppler provider uses the
  # owner's personal token (DOPPLER_TOKEN from task tf:*), which creating
  # service tokens needs on the free plan; that token never enters CI. CI
  # skips this stack with `--no-tags laptop-only`.
  tags = ["laptop-only"]
}

# What this stack needs generated (see terraform/terramate.tm.hcl). No
# doppler_writes: every Doppler write here goes through the default provider
# (the owner's token), so the stack that mints the write tokens never depends
# on them.
globals {
  providers                    = ["backblaze", "cloudflare", "github"]
  manages_doppler_write_tokens = true

  # The CI token's user-scoped policy needs the owner's Cloudflare user ID,
  # kept out of this public repo (MIGRATION.md step 0). Laptop-only: this key
  # stays out of tf-at-home/ci and ci-apply.
  secret_vars = {
    cloudflare_user_id = { project = "tf-at-home", key = "CLOUDFLARE_USER_ID" }
  }
}
