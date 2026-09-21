variable "tokens" {
  description = <<-EOT
    Values substituted into the name formats. Leave a token empty and it drops out
    cleanly, so a convention that has no <purpose> segment does not leave a double
    separator behind.

    env vs env_short exists because most conventions use a long form in dashed names
    and a shorter one where a type is tightly length-capped — IAM roles at 64
    characters, Lambda functions and EventBridge rules at 64.
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

    The path form is the *body* of a log group name — the leading /aws/lambda/ or
    /ecs/ segment comes from the spec's prefix, not from this format.
  EOT
  type        = map(string)
  default     = {}
}

variable "resource_specs" {
  description = <<-EOT
    Per-resource overrides, merged over the built-in table. Use this to change an
    abbreviation, to add a resource this module does not know about, or to set
    suffix = ".fifo" on the queue keys when running FIFO queues.

    form must be a key in formats. charset must be one of dash, underscore, iam,
    lowerdot, ddb, path, sqs, secret — these model the character rules AWS
    actually enforces per resource type, which differ more than Azure's do.
    max_length, charset and forbid_prefix are checked at plan time. prefix and
    suffix are counted against max_length.
  EOT
  # Every attribute defaults to null, not to a value: the spec is merged into the
  # built-in table per attribute, so omitting one keeps the built-in rather than
  # silently resetting it.
  type = map(object({
    type          = optional(string)
    form          = optional(string)
    max_length    = optional(number)
    lower         = optional(bool)
    charset       = optional(string)
    prefix        = optional(string)
    suffix        = optional(string)
    purpose       = optional(string)
    forbid_prefix = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for spec in values(var.resource_specs) :
      spec.charset == null || contains(["dash", "underscore", "iam", "lowerdot", "ddb", "path", "sqs", "secret"], spec.charset)
    ])
    error_message = "charset must be one of dash, underscore, iam, lowerdot, ddb, path, sqs, secret."
  }
}

variable "overrides" {
  description = <<-EOT
    Final names by resource key, bypassing the format entirely. The escape hatch for
    conventions no template expresses, and for adopting a platform that already has
    names in place. Still validated for length, charset and uniqueness.
  EOT
  type        = map(string)
  default     = {}
}
