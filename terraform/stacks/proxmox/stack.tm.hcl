stack {
  name        = "proxmox"
  description = "proxmox"
  id          = "c17753ff-4224-4901-aa83-53af40872024"

  # vms.tf reads these; an inventory change must re-plan the stack.
  watch = [
    "/inventory/hosts.yaml",
    "/inventory/sites.yaml",
    "/inventory/group_vars/all.yaml",
  ]
}

# What this stack needs generated (see terraform/terramate.tm.hcl).
globals {
  providers = ["cloudflare", "proxmox"]
}
