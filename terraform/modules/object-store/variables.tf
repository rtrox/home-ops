variable "backend" {
  description = "Where the bucket lives: b2 (Backblaze) or garage (the NAS). The B2-only inputs (bucket_type, lifecycle_rules, file_lock, and a key's capabilities and legacy_api) are refused with garage."
  type        = string
  default     = "b2"

  validation {
    condition     = contains(["b2", "garage"], var.backend)
    error_message = "backend must be \"b2\" or \"garage\"."
  }
}

variable "endpoint" {
  description = "The S3 endpoint URL consumers use, e.g. http://s3.nas.rtrox.io:3900. Required with garage; refused with b2, whose endpoint comes from the account."
  type        = string
  default     = null

  validation {
    condition     = var.backend == "garage" ? var.endpoint != null : var.endpoint == null
    error_message = "endpoint is required with backend = \"garage\" and refused with \"b2\"."
  }
}

variable "name" {
  description = "The bucket's name (B2 bucket names are global; Garage's is its global alias)."
  type        = string
}

variable "bucket_type" {
  description = "allPrivate, or allPublic (anyone can download). B2 only."
  type        = string
  default     = "allPrivate"

  validation {
    condition     = var.backend == "b2" || var.bucket_type == "allPrivate"
    error_message = "bucket_type is B2-only: a Garage bucket is private."
  }
}

variable "keys" {
  description = "Application keys limited to this bucket, by key name. `capabilities` replaces the default list (see main.tf) when set. `legacy_api` makes a key that clients older than B2's v4 API accept; changing it has no effect on an existing key (the plan says No changes), so add a second key instead."
  type = map(object({
    capabilities = optional(list(string))
    legacy_api   = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in values(var.keys) : k.capabilities == null || length(coalesce(k.capabilities, [])) > 0])
    error_message = "A key's capabilities must be non-empty when set."
  }

  validation {
    condition     = var.backend == "b2" || alltrue([for k in values(var.keys) : k.capabilities == null && !k.legacy_api])
    error_message = "A key's capabilities and legacy_api are B2-only: a Garage key gets read and write on this bucket."
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle rules (b2_bucket.lifecycle_rules), in the order B2 returns them. B2 only."
  type = list(object({
    file_name_prefix                                       = string
    days_from_uploading_to_hiding                          = optional(number)
    days_from_hiding_to_deleting                           = optional(number)
    days_from_starting_to_canceling_unfinished_large_files = optional(number)
  }))
  default = []

  validation {
    condition     = var.backend == "b2" || length(var.lifecycle_rules) == 0
    error_message = "lifecycle_rules is B2-only."
  }
}

variable "file_lock" {
  description = "B2 only. Object Lock (b2_bucket.file_lock_configuration). null leaves the bucket without it. Turning it on can't be undone, and on an existing bucket it means a replacement, which prevent_destroy refuses."
  type = object({
    default_retention = optional(object({
      mode     = string
      duration = number
      unit     = string
    }))
  })
  default = null

  validation {
    condition     = var.backend == "b2" || var.file_lock == null
    error_message = "file_lock is B2-only."
  }
}
