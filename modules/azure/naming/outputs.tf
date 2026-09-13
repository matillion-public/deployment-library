output "names" {
  description = "Resource key to resource name. Pass straight into a module's resource_names input."
  value       = local.names

  precondition {
    condition     = length(local.too_long) == 0
    error_message = "Names exceed the Azure limit for their resource type:\n  ${join("\n  ", local.too_long)}\nShorten a token, or set a shorter name for that key in overrides."
  }

  precondition {
    condition     = length(local.duplicates) == 0
    error_message = "The convention produces the same name for different resources:\n  ${join("\n  ", local.duplicates)}\nGive one of them a distinct purpose in resource_specs, or set an explicit name in overrides."
  }

  precondition {
    condition     = length(local.malformed) == 0
    error_message = "Names are not valid for their resource type:\n  ${join("\n  ", local.malformed)}"
  }
}
