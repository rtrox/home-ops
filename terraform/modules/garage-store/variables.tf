variable "name" {
  description = "The bucket's name (its Garage global alias)."
  type        = string
}

variable "endpoint" {
  description = "The S3 endpoint URL consumers use, e.g. http://s3.nas.rtrox.io:3900 (not the admin API)."
  type        = string
}

variable "keys" {
  description = "Keys limited to this bucket (read and write), by key name."
  type        = map(object({}))
  default     = {}
}
