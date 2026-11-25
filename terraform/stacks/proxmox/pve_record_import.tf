# The live record (its ID is in terraform-record's zone_rtrox_io.tf), which
# terraform-record's cloudflare stack forgets first (removed, destroy =
# false). Delete this file and pve-record-plan.json once applied.
import {
  to = cloudflare_dns_record.pve
  id = "9aedc7db6baa3b7dffd1e1ef54f7b7d2/4fdf2cba819cbe8968d9772daeeb77b6"
}
