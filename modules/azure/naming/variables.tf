variable "tokens" {
  description = <<-EOT
    Values substituted into the name formats. Leave a token empty and it drops out
    cleanly, so a convention that has no <purpose> segment does not leave a double
    separator behind.

    env vs env_short exists because most conventions use a long form in dashed names
    and a shorter one in the dashless, length-capped names (storage accounts and the
    like) — for example "p" against "pd".
  EOT
  type = object({
    bu        = optional(string, "")
    env       = optional(string, "")
    env_short = optional(string, "")
    region    = optional(string, "")
    purpose   = optional(string, "")
    instance  = optional(string, "")
  })
  default = {}
}

variable "formats" {
  description = <<-EOT
    Format string per name form. Tokens are {bu} {env} {envs} {region} {purpose}
    {type} {instance}; {type} is the resource abbreviation from resource_specs and
    {envs} is env_short. Override a form here to match a convention that orders or
    prefixes segments differently — for example prefixing subnets and route tables
    with a landing-zone marker.
  EOT
  type        = map(string)
  default     = {}
}

variable "resource_specs" {
  description = <<-EOT
    Per-resource overrides, merged over the built-in table. Use this to change an
    abbreviation, or to add a resource this module does not know about. form must be
    a key in formats. max_length and charset are enforced at plan time.
  EOT
  # Every attribute defaults to null, not to a value: the spec is merged into the
  # built-in table per attribute, so omitting one keeps the built-in rather than
  # silently resetting it.
  type = map(object({
    type       = optional(string)
    form       = optional(string)
    max_length = optional(number)
    lower      = optional(bool)
    purpose    = optional(string)
  }))
  default = {}
}

variable "overrides" {
  description = <<-EOT
    Final names by resource key, bypassing the format entirely. The escape hatch for
    conventions no template expresses, and for adopting a platform that already has
    names in place. Still validated for length and charset.
  EOT
  type        = map(string)
  default     = {}
}
