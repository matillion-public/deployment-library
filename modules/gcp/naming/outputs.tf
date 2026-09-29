output "names" {
  description = "Resource key to resource name. Pass straight into a module's resource_names input."
  value       = local.names

  precondition {
    condition     = length(local.too_long) == 0
    error_message = "Names exceed the GCP limit for their resource type:\n  ${join("\n  ", local.too_long)}\nShorten a token, or set a shorter name for that key in overrides. Service accounts cap at 30 characters and are usually the first to break."
  }

  precondition {
    condition     = length(local.too_short) == 0
    error_message = "Names are below the GCP minimum for their resource type:\n  ${join("\n  ", local.too_short)}\nLengthen a token, or set an explicit name for that key in overrides."
  }

  precondition {
    condition     = length(local.duplicates) == 0
    error_message = "The convention produces the same name for different resources:\n  ${join("\n  ", local.duplicates)}\nGive one of them a distinct purpose in resource_specs, or set an explicit name in overrides. On GCP this is often truncation: two service account names longer than 30 characters can collapse into one."
  }

  precondition {
    condition     = length(local.malformed) == 0
    error_message = "Names are not valid for their resource type:\n  ${join("\n  ", local.malformed)}\nMost GCP resources are RFC1035: lowercase, starting with a letter and ending alphanumeric."
  }
}
