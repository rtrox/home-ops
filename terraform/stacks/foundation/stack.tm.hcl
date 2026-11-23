stack {
  name        = "foundation"
  description = "Doppler projects, environments, configs and write tokens; the R2 state bucket and its tokens; CI's read-only credentials"
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
  providers                    = ["cloudflare"]
  manages_doppler_write_tokens = true
}
