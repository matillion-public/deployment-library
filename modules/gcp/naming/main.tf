locals {
  # purpose overrides tokens.purpose for that key alone. Several resources share an
  # abbreviation by convention — every service account is "sa" — so without a
  # distinguishing purpose they would generate the same name and collide on apply.
  #
  # GCP has fewer name sites than Azure or AWS but tighter rules. Most resource
  # types are RFC1035: lowercase, must start with a letter, end alphanumeric, 63
  # characters. The exceptions are what the charset and form fields exist for —
  # custom role ids reject hyphens outright, and service accounts cap at 30.
  default_specs = {
    # --- modules/gcp/networking -------------------------------------------------
    vpc        = { type = "vpc", max_length = 63, charset = "rfc1035" }
    subnet     = { type = "snet", max_length = 63, charset = "rfc1035" }
    nat_router = { type = "rtr", max_length = 63, charset = "rfc1035", purpose = "nat" }
    nat_ip     = { type = "addr", max_length = 63, charset = "rfc1035", purpose = "nat" }
    cloud_nat  = { type = "nat", max_length = 63, charset = "rfc1035" }

    # Secondary ranges live on the subnet. The GKE cluster reads them back through
    # the networking module's outputs, so naming them here keeps both sides in step.
    pod_secondary_range      = { type = "pods", max_length = 63, charset = "rfc1035" }
    services_secondary_range = { type = "svcs", max_length = 63, charset = "rfc1035" }

    # --- modules/gcp/gke --------------------------------------------------------
    # Clusters and node pools cap at 40, tighter than the usual 63.
    gke_cluster = { type = "gke", max_length = 40, charset = "rfc1035" }
    node_pool   = { type = "np", max_length = 40, charset = "rfc1035" }

    # A network tag, not a resource name — firewall rules target it.
    gke_node_network_tag = { type = "node", max_length = 63, charset = "rfc1035" }

    # 30 characters is the binding constraint on this platform. A six-segment
    # convention will not fit, which is why the README calls these out as the keys
    # most likely to need an explicit override.
    node_service_account            = { type = "sa", max_length = 30, min_length = 6, charset = "rfc1035", purpose = "node" }
    runner_workload_service_account = { type = "sa", max_length = 30, min_length = 6, charset = "rfc1035", purpose = "runnerwl" }

    # Buckets are globally unique and allow underscores and dots, unlike the
    # RFC1035 types, but must still start and end alphanumeric.
    staging_bucket = { type = "gcs", max_length = 63, min_length = 3, lower = true, charset = "gcs", purpose = "staging" }

    runner_secret = { type = "secret", max_length = 255, charset = "secret", purpose = "runner" }

    # A custom role id rejects hyphens, so it takes the underscore form. This is
    # the charset conflict the module exists to handle rather than paper over.
    runner_secret_creator_role = { type = "secretcreator", form = "underscore", max_length = 64, min_length = 3, charset = "role", purpose = "runner" }

    # --- modules/gcp/runner-identity --------------------------------------------
    runner_service_account = { type = "sa", max_length = 30, min_length = 6, charset = "rfc1035", purpose = "runner" }
  }

  default_formats = {
    dashed = "{bu}-{env}-{region}-{purpose}-{type}-{instance}"
    # Custom role ids reject hyphens. Separate format rather than a post-hoc
    # replace(), so a convention is validated as written instead of being rewritten
    # after the uniqueness check has already run against the other spelling.
    underscore = "{bu}_{env}_{region}_{purpose}_{type}_{instance}"
  }

  # Anchored so a name that is right except for one stray character still fails.
  charsets = {
    # RFC1035: the rule behind most GCP resource names. Must start with a letter,
    # which is the check Azure never needed.
    rfc1035 = "^[a-z]([-a-z0-9]*[a-z0-9])?$"
    # GCS buckets: lowercase, and dots and underscores are allowed.
    gcs = "^[a-z0-9][a-z0-9._-]*[a-z0-9]$"
    # Secret Manager ids allow uppercase and underscores but not dots.
    secret = "^[A-Za-z0-9_-]+$"
    # Custom role ids: letters, digits, underscores and dots. No hyphens.
    role = "^[a-zA-Z][a-zA-Z0-9_.]*$"
  }

  formats = merge(local.default_formats, var.formats)

  # Per-attribute merge, not a whole-object replace. merge() swaps the entire spec,
  # and because resource_specs carries its own attribute defaults, a partial
  # override like { type = "sa" } would silently reset max_length, min_length and
  # charset — passing the plan and then failing at apply on the real GCP limit.
  specs = {
    for key in distinct(concat(keys(local.default_specs), keys(var.resource_specs))) :
    key => {
      type       = try(var.resource_specs[key].type, null) != null ? var.resource_specs[key].type : try(local.default_specs[key].type, null)
      form       = try(var.resource_specs[key].form, null) != null ? var.resource_specs[key].form : try(local.default_specs[key].form, "dashed")
      max_length = try(var.resource_specs[key].max_length, null) != null ? var.resource_specs[key].max_length : try(local.default_specs[key].max_length, 63)
      min_length = try(var.resource_specs[key].min_length, null) != null ? var.resource_specs[key].min_length : try(local.default_specs[key].min_length, 1)
      lower      = try(var.resource_specs[key].lower, null) != null ? var.resource_specs[key].lower : try(local.default_specs[key].lower, false)
      charset    = try(var.resource_specs[key].charset, null) != null ? var.resource_specs[key].charset : try(local.default_specs[key].charset, "rfc1035")
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
  # collapses to its own first character, which keeps the underscore form (used by
  # custom role ids, where a hyphen is invalid) underscore-separated without
  # needing to special-case the form.
  tidied = {
    for key, value in local.substituted :
    key => trim(replace(value, "/([-_])[-_]+/", "$1"), "-_")
  }

  # Deliberately not truncated. Cutting a name to length silently drops the {type}
  # and {instance} segments, so two deployments differing only by instance collapse
  # onto the same name — and for a globally unique type like a storage bucket the
  # second fails at apply, in a separate state where the duplicate check below
  # cannot see it. On GCP this was especially sharp: three service accounts share
  # the "sa" abbreviation and a 30-character cap. Too long is a convention error and
  # fails the plan instead.
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

  # GCP enforces minimums as well as maximums: 6 for service accounts, 3 for
  # buckets and custom roles. Truncating into a too-short name fails at apply
  # otherwise, which is the least helpful place to find out.
  too_short = [
    for key, value in local.names :
    "${key} = \"${value}\" is ${length(value)} characters, minimum is ${local.specs[key].min_length}"
    if contains(keys(local.specs), key) && length(value) < local.specs[key].min_length
  ]

  # Two keys generating the same name is the failure mode this module exists to
  # prevent. On GCP it is especially easy to hit: service accounts are capped at
  # 30 characters, so two distinct names can truncate into one.
  duplicates = [
    for name, keys in { for key, value in local.names : value => key... } :
    "${name} is generated for more than one resource: ${join(", ", sort(keys))}"
    if length(keys) > 1
  ]

  malformed = concat(
    [
      for key, value in local.names :
      "${key} = \"${value}\" must match the ${local.specs[key].charset} character set for its resource type (${local.charsets[local.specs[key].charset]})"
      if contains(keys(local.specs), key) &&
      length(regexall(local.charsets[local.specs[key].charset], value)) == 0
    ],
    [
      for key, value in local.names :
      "${key} = \"${value}\" must be lowercase"
      if contains(keys(local.specs), key) && local.specs[key].lower && value != lower(value)
    ]
  )
}
