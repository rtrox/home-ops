variable "name" {
  description = "The bucket's name (B2 bucket names are global)."
  type        = string
}

variable "bucket_type" {
  description = "allPrivate, or allPublic (anyone can download)."
  type        = string
  default     = "allPrivate"
}

variable "keys" {
  description = "Application keys limited to this bucket, by key name. `capabilities` replaces the default list (see main.tf) when set. `legacy_api` makes a key that clients older than B2's v4 API accept; changing it replaces the key, so add a second key instead."
  type = map(object({
    capabilities = optional(list(string))
    legacy_api   = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in values(var.keys) : k.capabilities == null || length(coalesce(k.capabilities, [])) > 0])
    error_message = "A key's capabilities must be non-empty when set."
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle rules (b2_bucket.lifecycle_rules), in the order B2 returns them."
  type = list(object({
    file_name_prefix                                       = string
    days_from_uploading_to_hiding                          = optional(number)
    days_from_hiding_to_deleting                           = optional(number)
    days_from_starting_to_canceling_unfinished_large_files = optional(number)
  }))
  default = []
}

variable "file_lock" {
  description = "Object Lock (b2_bucket.file_lock_configuration). null leaves the bucket without it. Turning it on can't be undone, and on an existing bucket it means a replacement, which prevent_destroy refuses."
  type = object({
    default_retention = optional(object({
      mode     = string
      duration = number
      unit     = string
    }))
  })
  default = null
}
