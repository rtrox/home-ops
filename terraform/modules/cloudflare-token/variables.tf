variable "name" {
  description = "The token's name; the issue date is appended (<name>-YYYY-MM-DD)."
  type        = string
}

variable "permissions" {
  description = "Permission group names, as Cloudflare lists them (e.g. \"Zone Read\", \"DNS Write\"). All are granted on var.zone_ids only, so only zone-level groups belong here."
  type        = list(string)

  validation {
    condition     = length(var.permissions) > 0
    error_message = "A token needs at least one permission group."
  }
}

variable "zone_ids" {
  description = "IDs of the zones the token is limited to. Never empty: this module doesn't make account-wide tokens."
  type        = list(string)

  validation {
    condition     = length(var.zone_ids) > 0 && alltrue([for id in var.zone_ids : can(regex("^[0-9a-f]{32}$", id))])
    error_message = "zone_ids must be one or more 32-character hex Cloudflare zone IDs."
  }
}

variable "rotation_days" {
  description = "Reissue the token every this many days (at the first apply after)."
  type        = number
  default     = 90
}

variable "lifetime_days" {
  description = "Each token expires this many days after its issue. Must exceed rotation_days by enough to cover applies that lapse."
  type        = number
  default     = 180

  validation {
    condition     = var.lifetime_days > var.rotation_days + 30
    error_message = "lifetime_days must be more than rotation_days + 30, or the expiry check fires before the token is due for reissue."
  }
}
