# Debian 13 cloud-init template and the VMs cloned from it. Addresses, prefix and
# gateway come from inventory/ (hosts.yaml, sites.yaml); nothing about the network
# is written here, so renumbering a site is an inventory edit.
#
# The runner never manages its own VM: prevent_destroy on all three, and this
# stack is applied from the laptop, never by the runner.
#
# TODO: back these VMs up with vzdump to the NAS (issue #2135).
locals {
  inventory_hosts = yamldecode(file("${path.module}/../../../inventory/hosts.yaml"))
  inventory_sites = yamldecode(file("${path.module}/../../../inventory/sites.yaml"))

  inventory_vm_hosts = local.inventory_hosts.all.children.vms.hosts

  pve_node  = "pve"
  vm_bridge = "vmbr0"
  # Until the apartment resolvers exist (#9); then dns-a1 and dns-a2.
  vm_dns_server = "1.1.1.1"

  template_vmid = 9000

  # Keys are the short hostnames (also the VM names); fqdn is the inventory key.
  vms = {
    runner = {
      fqdn      = "runner.rtrox.io"
      vmid      = 110
      cores     = 4
      memory    = 8192
      disk_size = 64
    }
    dns-a1 = {
      fqdn      = "dns-a1.rtrox.io"
      vmid      = 120
      cores     = 2
      memory    = 2048
      disk_size = 16
    }
  }

  # Per-VM network, resolved from the inventory: the host's address, and the
  # prefix and gateway of the VLAN it sits in.
  vm_vlan = {
    for name, vm in local.vms : name => local.inventory_sites.sites[
      local.inventory_vm_hosts[vm.fqdn].site
    ].vlans[local.inventory_vm_hosts[vm.fqdn].vlan]
  }

  vm_network = {
    for name, vm in local.vms : name => {
      address = local.inventory_vm_hosts[vm.fqdn].address
      prefix  = tonumber(split("/", local.vm_vlan[name].cidr)[1])
      gateway = local.vm_vlan[name].router
    }
  }

  # The same default user Ansible connects as (one source for both).
  ssh_user = yamldecode(file("${path.module}/../../../inventory/group_vars/all.yaml")).ansible_user
  # One key per line; drop blank lines.
  ssh_keys = [for k in split("\n", data.http.github_keys.response_body) : trimspace(k) if trimspace(k) != ""]
}

data "http" "github_keys" {
  url = "https://github.com/rtrox.keys"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && length(trimspace(self.response_body)) > 0
      error_message = "Fetching the GitHub SSH keys failed or returned none."
    }
  }
}

# Debian 13 "trixie" genericcloud, pinned to a dated build (not "latest").
# Checksum from
# https://cloud.debian.org/images/cloud/trixie/20261116-2664/SHA512SUMS
resource "proxmox_download_file" "debian13" {
  node_name = local.pve_node
  # `local` is a dir datastore with the `import` content type enabled.
  datastore_id       = "local"
  content_type       = "import"
  file_name          = "debian-13-genericcloud-amd64-20261116-2664.qcow2"
  url                = "https://cloud.debian.org/images/cloud/trixie/20261116-2664/debian-13-genericcloud-amd64-20261116-2664.qcow2"
  checksum           = "37cb32b320820417eb04b335afcf489bfb4cecce4a957190d09cb2bffbe02b56a1cadd62d78c6ead92aa7839d5ea65e4260f994bbb4b54490df59fdf11ee1d97"
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_vm" "debian13_template" {
  node_name = local.pve_node
  vm_id     = local.template_vmid
  name      = "debian-13-cloud"
  template  = true
  started   = false

  description = "Debian 13 cloud-init template, managed by OpenTofu (terraform/stacks/proxmox)."
  tags        = ["debian13", "template"]

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  agent {
    enabled = true
    # The cloud image ships without qemu-guest-agent (Ansible installs it), so
    # don't wait for it to report an IP on create or refresh. Once installed,
    # the agent works without a Terraform change.
    wait_for_ip {
      disabled = true
    }
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = proxmox_download_file.debian13.id
    size         = 8 # GiB; clones grow it (see local.vms)
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = local.vm_bridge
    model  = "virtio"
  }

  # Cloud images expect a serial console.
  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  # Creates the cloud-init drive, which clones inherit.
  initialization {
    datastore_id = "local-lvm"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  node_name = local.pve_node
  vm_id     = each.value.vmid
  name      = each.key

  description = "${each.value.fqdn}, managed by OpenTofu (terraform/stacks/proxmox)."
  tags        = ["debian13"]

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true

  clone {
    vm_id        = proxmox_virtual_environment_vm.debian13_template.vm_id
    datastore_id = "local-lvm"
    full         = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
    # The cloud image ships without qemu-guest-agent (Ansible installs it), so
    # don't wait for it to report an IP on create or refresh. Once installed,
    # the agent works without a Terraform change.
    wait_for_ip {
      disabled = true
    }
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = local.vm_bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = [local.vm_dns_server]
    }

    ip_config {
      ipv4 {
        address = "${local.vm_network[each.key].address}/${local.vm_network[each.key].prefix}"
        gateway = local.vm_network[each.key].gateway
      }
    }

    user_account {
      username = local.ssh_user
      keys     = local.ssh_keys
    }
  }

  lifecycle {
    prevent_destroy = true
    # cloud-init's user and keys apply at first boot only. Changing them later
    # (e.g. a new key on GitHub) would reboot the VM and, because Proxmox
    # derives the cloud-init instance-id from the user-data, re-run cloud-init
    # as a new instance (new SSH host keys). Ansible manages keys after boot.
    # ip_config and dns stay managed, so renumbering via the inventory works.
    ignore_changes = [initialization[0].user_account]

    precondition {
      # A plain Linux username: rejects empty, null and a templated value.
      condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", coalesce(local.ssh_user, "")))
      error_message = "ansible_user in inventory/group_vars/all.yaml is empty."
    }
  }
}

# Internal names. They point at private addresses on purpose (same pattern as
# the other internal records); the zone comes from acme_token.tf's data source.
resource "cloudflare_dns_record" "vm" {
  for_each = local.vms

  zone_id = data.cloudflare_zone.rtrox_io.zone_id
  name    = local.inventory_vm_hosts[each.value.fqdn].dns_name
  type    = "A"
  content = local.vm_network[each.key].address
  ttl     = 1
  proxied = false
  comment = "Proxmox VM, managed by OpenTofu (terraform/stacks/proxmox)"
}
