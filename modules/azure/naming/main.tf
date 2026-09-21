locals {
  # purpose overrides tokens.purpose for that key alone. Several resources share an
  # abbreviation by convention — every managed identity is "id" — so without a
  # distinguishing purpose they would generate the same name and collide on apply.
  default_specs = {
    vnet          = { type = "vnet", form = "dashed", max_length = 64 }
    nsg           = { type = "nsg", form = "dashed", max_length = 80 }
    nat_gateway   = { type = "natgw", form = "dashed", max_length = 80 }
    nat_public_ip = { type = "pip", form = "dashed", max_length = 80 }
    aks_cluster   = { type = "aks", form = "dashed", max_length = 63 }
    log_workspace = { type = "log", form = "dashed", max_length = 63 }
    key_vault     = { type = "kv", form = "dashed", max_length = 24 }

    container_app             = { type = "ca", form = "dashed", max_length = 32 }
    container_app_environment = { type = "cae", form = "dashed", max_length = 60 }
    servicebus_namespace      = { type = "sbns", form = "dashed", max_length = 50 }
    script_runner_app         = { type = "ca", form = "dashed", max_length = 32, purpose = "scriptrunner" }
    state_resource_group      = { type = "rg", form = "dashed", max_length = 90, purpose = "tfstate" }

    aks_identity           = { type = "id", form = "dashed", max_length = 128, purpose = "aks" }
    runner_identity        = { type = "id", form = "dashed", max_length = 128, purpose = "runner" }
    container_app_identity = { type = "id", form = "dashed", max_length = 128, purpose = "ca" }
    queue_adapter_identity = { type = "id", form = "dashed", max_length = 128, purpose = "queueadapter" }
    # container-apps runs its own script-runner identity alongside the app identity,
    # so it needs its own key rather than borrowing the runner's.
    script_runner_identity = { type = "id", form = "dashed", max_length = 128, purpose = "scriptrunner" }

    # modules/azure/runner-identity is one identity per runner deployment and can be
    # composed alongside aks, which creates its own. Distinct keys keep the two from
    # generating the same name — the duplicate check compares key against key, so it
    # cannot see one key consumed by two resources.
    tenant_runner_identity = { type = "id", form = "dashed", max_length = 128, purpose = "tenantrunner" }

    runner_federated_credential               = { type = "fic", form = "dashed", max_length = 120, purpose = "runner" }
    script_runner_federated_credential        = { type = "fic", form = "dashed", max_length = 120, purpose = "scriptrunner" }
    tenant_runner_federated_credential        = { type = "fic", form = "dashed", max_length = 120, purpose = "tenantrunner" }
    tenant_script_runner_federated_credential = { type = "fic", form = "dashed", max_length = 120, purpose = "tenantscriptrunner" }

    storage_account       = { type = "st", form = "dashless", max_length = 24, lower = true }
    queue_storage_account = { type = "st", form = "dashless", max_length = 24, lower = true, purpose = "queue" }
    # addon/queue-azure-storage and azure/queue-adapter-job each create a storage
    # account; they are alternative queue backends, not companions, so they get
    # separate keys to keep the uniqueness check meaningful.
    trigger_storage_account = { type = "st", form = "dashless", max_length = 24, lower = true, purpose = "trigger" }
    state_storage_account   = { type = "st", form = "dashless", max_length = 24, lower = true, purpose = "tfstate" }
    state_container         = { type = "stct", form = "dashed", max_length = 63, lower = true, purpose = "tfstate" }
  }

  default_formats = {
    dashed   = "{bu}-{env}-{region}-{purpose}-{type}-{instance}"
    dashless = "{bu}{envs}{region}{purpose}{type}{instance}"
  }

  formats = merge(local.default_formats, var.formats)

  # Per-attribute merge, not a whole-object replace. merge() swaps the entire spec,
  # and because resource_specs carries its own attribute defaults, a partial
  # override like { type = "akv" } would silently reset max_length, lower and
  # purpose — passing the plan and then failing at apply on the real Azure limit.
  specs = {
    for key in distinct(concat(keys(local.default_specs), keys(var.resource_specs))) :
    key => {
      type       = try(var.resource_specs[key].type, null) != null ? var.resource_specs[key].type : try(local.default_specs[key].type, null)
      form       = try(var.resource_specs[key].form, null) != null ? var.resource_specs[key].form : try(local.default_specs[key].form, "dashed")
      max_length = try(var.resource_specs[key].max_length, null) != null ? var.resource_specs[key].max_length : try(local.default_specs[key].max_length, 80)
      lower      = try(var.resource_specs[key].lower, null) != null ? var.resource_specs[key].lower : try(local.default_specs[key].lower, false)
      purpose    = try(var.resource_specs[key].purpose, null) != null ? var.resource_specs[key].purpose : try(local.default_specs[key].purpose, null)
    }
  }

  # Braces keep tokens from being prefixes of one another, so substitution order
  # does not matter — {env} cannot partially match {envs}.
  substituted = {
    for key, spec in local.specs : key => replace(replace(replace(replace(replace(replace(replace(
      lookup(local.formats, spec.form, local.default_formats.dashed),
      "{bu}", var.tokens.bu),
      "{envs}", var.tokens.env_short),
      "{env}", var.tokens.env),
      "{region}", var.tokens.region),
      "{purpose}", spec.purpose == null ? var.tokens.purpose : spec.purpose),
      "{type}", spec.type),
    "{instance}", var.tokens.instance)
  }

  # Empty tokens leave doubled or trailing separators behind; collapse them so a
  # convention without a purpose segment still produces a clean name. A run
  # collapses to its own first character rather than always to a hyphen, because
  # formats is an advertised override point and an underscore-separated convention
  # would otherwise come back with mixed separators.
  tidied = {
    for key, value in local.substituted :
    key => trim(replace(value, "/([-_])[-_]+/", "$1"), "-_")
  }

  # Deliberately not truncated. Cutting a name to length silently drops the {type}
  # and {instance} segments, so two deployments differing only by instance collapse
  # onto the same name — and for a globally unique type like a storage account the
  # second fails at apply, in a separate state where the duplicate check below
  # cannot see it. Too long is a convention error, so it fails the plan instead.
  generated = {
    for key, spec in local.specs :
    key => spec.lower ? lower(local.tidied[key]) : local.tidied[key]
  }

  # An explicit override wins over anything generated.
  names = merge(local.generated, var.overrides)

  too_long = [
    for key, value in local.names :
    "${key} = \"${value}\" is ${length(value)} characters, limit is ${local.specs[key].max_length}"
    if contains(keys(local.specs), key) && length(value) > local.specs[key].max_length
  ]

  # Azure is broadly permissive here, but every resource this module names rejects
  # a leading or trailing separator, and storage accounts reject anything that is
  # not lowercase alphanumeric.
  # Two keys generating the same name is the failure mode this module exists to
  # prevent — it surfaces as a confusing apply error, or silently reuses a resource.
  duplicates = [
    for name, keys in { for key, value in local.names : value => key... } :
    "${name} is generated for more than one resource: ${join(", ", sort(keys))}"
    if length(keys) > 1
  ]

  malformed = concat(
    [
      for key, value in local.names :
      "${key} = \"${value}\" must not start or end with a separator"
      if length(regexall("^[-_]|[-_]$", value)) > 0
    ],
    # The dashless form exists for resources that reject separators entirely --
    # storage accounts and registries. Lowercase is a separate constraint: a storage
    # container is lowercase but does allow hyphens.
    [
      for key, value in local.names :
      "${key} = \"${value}\" must be lowercase alphanumeric with no separators"
      if contains(keys(local.specs), key) && local.specs[key].form == "dashless" &&
      length(regexall("^[a-z0-9]+$", value)) == 0
    ],
    [
      for key, value in local.names :
      "${key} = \"${value}\" must be lowercase"
      if contains(keys(local.specs), key) && local.specs[key].lower &&
      value != lower(value)
    ]
  )
}
