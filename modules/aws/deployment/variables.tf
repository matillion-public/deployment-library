variable "use_existing_vpc" {
  type = bool
}

variable "existing_vpc_id" {
  type = string
}
variable "name" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "random_string_salt" {
  type = string
}

variable "use_existing_subnet" {
  type    = bool
  default = false
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/aws/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
