stack {
  name        = "truenas"
  description = "The two TrueNAS hosts' A records, the main TrueNAS's cloud-sync B2 bucket and key, and Garage (S3) on the main TrueNAS"
  id          = "b971bcc6-8fdc-431f-9266-ca7eb58d9ffb"

  # Applied by CI on merge (terraform-apply.yaml), like dns. A plan with a
  # destroy, replace or forget, or a create of truenas_cloud_sync
  # (TF_GATE_ON_CREATE), waits for the owner's approval in tofu-apply-gated.
  # Laptop-only until Nov 2026 (README.md, "In CI").
  tags = ["ci-apply"]

  # records.tf builds both A records from it (each host's dns_name and
  # address). An address edit, such as the NAS's renumber at its move
  # (`moves_to`), changes the live record at the next apply.
  watch = [
    "/inventory/hosts.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers      = ["backblaze", "cloudflare", "truenas"]
  doppler_writes = ["hosts-at-home/prd"]

  # Its own Cloudflare token (foundation's truenas_token.tf): Zone Read and DNS
  # Write on rtrox.io, nothing else. The TrueNAS ACME tokens are foundation's
  # (truenas_acme_tokens.tf), so this stack can't mint tokens.
  provider_keys = { cloudflare = "CLOUDFLARE_TRUENAS_TOKEN" }
}
