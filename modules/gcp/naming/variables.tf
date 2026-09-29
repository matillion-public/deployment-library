variable "tokens" {
  description = <<-EOT
    Values substituted into the name formats. Leave a token empty and it drops out
    cleanly, so a convention that has no <purpose> segment does not leave a double
    separator behind.

    env vs env_short exists because most conventions use a long form in general
    names and a shorter one where a type is tightly capped. On GCP that matters
    more than elsewhere: service accounts allow 30 characters, and clusters and
    node pools 40.

    Tokens must be lowercase and start with a letter for the RFC1035 resource
    types, which is most of them.
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
    prefixes segments differently.

    Two forms ship: dashed for everything RFC1035, and underscore for custom role
    ids, which reject hyphens.
  EOT
  type        = map(string)
  default     = {}
}

variable "resource_specs" {
  description = <<-EOT
    Per-resource overrides, merged over the built-in table. Use this to change an
    abbreviation or to add a resource this module does not know about.

    form must be a key in formats. charset must be one of rfc1035, gcs, secret,
    role — these model the character rules GCP actually enforces per resource type.
    max_length, min_length and charset are checked at plan time; GCP enforces
    minimums as well as maximums, so both are real.
  EOT
  # Every attribute defaults to null, not to a value: the spec is merged into the
  # built-in table per attribute, so omitting one keeps the built-in rather than
  # silently resetting it.
  type = map(object({
    type       = optional(string)
    form       = optional(string)
    max_length = optional(number)
    min_length = optional(number)
    lower      = optional(bool)
    charset    = optional(string)
    purpose    = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for spec in values(var.resource_specs) :
      spec.charset == null || contains(["rfc1035", "gcs", "secret", "role"], spec.charset)
    ])
    error_message = "charset must be one of rfc1035, gcs, secret, role."
  }
}

variable "overrides" {
  description = <<-EOT
    Final names by resource key, bypassing the format entirely. The escape hatch for
    conventions no template expresses, and for adopting a platform that already has
    names in place. Still validated for length, charset and uniqueness.

    This is the expected route for the three service account keys on any convention
    that does not fit inside 30 characters.
  EOT
  type        = map(string)
  default     = {}
}
