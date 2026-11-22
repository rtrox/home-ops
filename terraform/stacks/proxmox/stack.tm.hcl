stack {
  name        = "proxmox"
  description = "proxmox"
  id          = "c17753ff-4224-4901-aa83-53af40872024"
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare", "proxmox"]
}
