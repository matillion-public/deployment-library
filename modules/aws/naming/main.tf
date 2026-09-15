locals {
  # purpose overrides tokens.purpose for that key alone. Several resources share an
  # abbreviation by convention — every IAM role is "role" — so without a
  # distinguishing purpose they would generate the same name and collide on apply.
  #
  # charset is the AWS-specific part. Azure gets away with two forms because its
  # resource types are broadly consistent; AWS resource types are not. IAM accepts
  # +=,.@_- , S3 wants lowercase with dots, log groups are paths, SQS allows
  # underscores and a .fifo suffix. Each is enforced at plan time.
  default_specs = {
    # --- modules/aws/deployment -------------------------------------------------
    # These are Name *tag* values, not resource identities: the VPC, subnets,
    # gateways and route tables have no name argument. Tag values allow 256
    # characters and almost any character, so the limit here is deliberately loose.
    vpc                 = { type = "vpc", max_length = 255 }
    internet_gateway    = { type = "igw", max_length = 255 }
    public_route_table  = { type = "rtb", max_length = 255, purpose = "public" }
    private_route_table = { type = "rtb", max_length = 255, purpose = "private" }
    public_subnet       = { type = "snet", max_length = 255, purpose = "public" }
    private_subnet      = { type = "snet", max_length = 255, purpose = "private" }
    nat_eip             = { type = "eip", max_length = 255, purpose = "nat" }
    nat_gateway         = { type = "natgw", max_length = 255 }

    # A real identity, unlike everything above it.
    k8s_security_group = { type = "sg", max_length = 255, purpose = "k8s", forbid_prefix = "sg-" }

    # --- modules/aws/ecs --------------------------------------------------------
    staging_bucket               = { type = "s3", max_length = 63, lower = true, charset = "lowerdot", purpose = "staging" }
    ecs_security_group           = { type = "sg", max_length = 255, purpose = "runner", forbid_prefix = "sg-" }
    ecs_cluster                  = { type = "ecs", max_length = 255 }
    ecs_task_family              = { type = "ecstask", max_length = 255, charset = "underscore" }
    ecs_service                  = { type = "ecssvc", max_length = 255 }
    service_discovery_namespace  = { type = "sdns", max_length = 253, charset = "lowerdot", lower = true }
    ecs_task_log_group           = { type = "log", form = "path", prefix = "/ecs/", max_length = 512, charset = "path" }
    script_runner_security_group = { type = "sg", max_length = 255, purpose = "scriptrunner", forbid_prefix = "sg-" }
    script_runner_log_group      = { type = "log", form = "path", prefix = "/ecs/", max_length = 512, charset = "path", purpose = "scriptrunner" }
    script_runner_task_family    = { type = "ecstask", max_length = 255, charset = "underscore", purpose = "scriptrunner" }
    script_runner_service        = { type = "ecssvc", max_length = 255, purpose = "scriptrunner" }

    # --- modules/aws/eks --------------------------------------------------------
    # 64 characters is the IAM role ceiling and the binding constraint across this
    # module and modules/aws/iam. Keep role type codes short.
    eks_cluster                = { type = "eks", max_length = 100, charset = "underscore" }
    eks_role                   = { type = "role", max_length = 64, charset = "iam", purpose = "eks" }
    fargate_pod_execution_role = { type = "role", max_length = 64, charset = "iam", purpose = "fargatepod" }
    service_account_role       = { type = "role", max_length = 64, charset = "iam", purpose = "sa" }
    dpc_policy                 = { type = "policy", max_length = 128, charset = "iam", purpose = "dpcaccess" }
    fargate_profile            = { type = "fgp", max_length = 63 }
    log_bucket                 = { type = "s3", max_length = 63, lower = true, charset = "lowerdot", purpose = "logs" }
    eks_secret                 = { type = "secret", max_length = 512, charset = "secret", purpose = "eks" }

    # --- modules/aws/iam --------------------------------------------------------
    ecs_task_role                     = { type = "role", max_length = 64, charset = "iam", purpose = "ecstask" }
    ecs_task_execution_role           = { type = "role", max_length = 64, charset = "iam", purpose = "ecsexec" }
    script_runner_task_role           = { type = "role", max_length = 64, charset = "iam", purpose = "scriptrunner" }
    ecs_task_instance_profile         = { type = "instprof", max_length = 128, charset = "iam", purpose = "ecstask" }
    ecs_task_role_policy              = { type = "policy", max_length = 128, charset = "iam", purpose = "ecstask" }
    ecs_task_execution_secret_policy  = { type = "policy", max_length = 128, charset = "iam", purpose = "ecsexecsecret" }
    ecs_task_execution_keypair_policy = { type = "policy", max_length = 128, charset = "iam", purpose = "ecsexeckeypair" }
    script_runner_s3_policy           = { type = "policy", max_length = 128, charset = "iam", purpose = "scriptrunners3" }

    # --- modules/aws/runner-identity --------------------------------------------
    runner_role           = { type = "role", max_length = 64, charset = "iam", purpose = "runner" }
    runner_secrets_policy = { type = "policy", max_length = 128, charset = "iam", purpose = "runnersecrets" }
    runner_s3_policy      = { type = "policy", max_length = 128, charset = "iam", purpose = "runners3" }

    # --- modules/aws/state-management -------------------------------------------
    state_bucket     = { type = "s3", max_length = 63, lower = true, charset = "lowerdot", purpose = "tfstate" }
    state_lock_table = { type = "ddb", max_length = 255, charset = "ddb", purpose = "tfstate" }

    # --- modules/aws/lambda/saturation-monitor ----------------------------------
    # No key for the Lambda log groups. Lambda writes to /aws/lambda/<function-name>
    # and that is not a free choice, so modules/aws/lambda/* derive the log group
    # name from the function key rather than letting the two drift apart. The ECS
    # log groups below are genuinely nameable, which is why they do have keys.
    saturation_function          = { type = "fn", max_length = 64, purpose = "saturation" }
    saturation_lambda_role       = { type = "role", max_length = 64, charset = "iam", purpose = "saturation" }
    saturation_lambda_policy     = { type = "policy", max_length = 128, charset = "iam", purpose = "saturation" }
    saturation_lambda_sg         = { type = "sg", max_length = 255, purpose = "saturation", forbid_prefix = "sg-" }
    saturation_schedule_rule     = { type = "rule", max_length = 64, purpose = "saturation" }
    saturation_dashboard         = { type = "dash", max_length = 255, charset = "underscore", purpose = "saturation" }
    saturation_alarm_task        = { type = "alarm", max_length = 255, purpose = "tasksaturation" }
    saturation_alarm_queue       = { type = "alarm", max_length = 255, purpose = "requestqueue" }
    saturation_alarm_errors      = { type = "alarm", max_length = 255, purpose = "saturationerrors" }
    vpc_endpoints_security_group = { type = "sg", max_length = 255, purpose = "vpce", forbid_prefix = "sg-" }
    # Interface endpoints, like the networking resources above, are Name tags only.
    vpc_endpoint_ecs        = { type = "vpce", max_length = 255, purpose = "ecs" }
    vpc_endpoint_cloudwatch = { type = "vpce", max_length = 255, purpose = "cloudwatch" }
    vpc_endpoint_logs       = { type = "vpce", max_length = 255, purpose = "logs" }

    # --- modules/aws/lambda/sqs-dpc-adapter -------------------------------------
    # SQS caps at 80 characters, and a FIFO queue's name must end ".fifo" — set
    # suffix = ".fifo" on these keys when fifo_queue is on. The suffix is counted
    # against max_length, so a name is truncated to leave room for it.
    adapter_function        = { type = "fn", max_length = 64, purpose = "sqsadapter" }
    adapter_role            = { type = "role", max_length = 64, charset = "iam", purpose = "sqsadapter" }
    adapter_policy          = { type = "policy", max_length = 128, charset = "iam", purpose = "sqsadapter" }
    adapter_source_queue    = { type = "sqs", max_length = 80, charset = "sqs", purpose = "sqssource" }
    adapter_source_dlq      = { type = "sqs", max_length = 80, charset = "sqs", purpose = "sqssourcedlq" }
    adapter_lambda_dlq      = { type = "sqs", max_length = 80, charset = "sqs", purpose = "sqsadapterdlq" }
    adapter_mapping_table   = { type = "ddb", max_length = 255, charset = "ddb", purpose = "projectmapping" }
    adapter_alerts_topic    = { type = "sns", max_length = 256, purpose = "sqsadapteralerts" }
    adapter_alarm_dlq       = { type = "alarm", max_length = 255, purpose = "dlqmessages" }
    adapter_alarm_errors    = { type = "alarm", max_length = 255, purpose = "sqsadaptererrors" }
    adapter_alarm_throttles = { type = "alarm", max_length = 255, purpose = "sqsadapterthrottles" }

    # --- modules/addon/queue-sqs ------------------------------------------------
    # The composer add-on is an alternative to the module above, not a companion,
    # but both sets of keys live in one map — so they carry distinct purposes to
    # keep the uniqueness check meaningful.
    trigger_queue            = { type = "sqs", max_length = 80, charset = "sqs", purpose = "triggers" }
    trigger_dlq              = { type = "sqs", max_length = 80, charset = "sqs", purpose = "triggersdlq" }
    trigger_adapter_dlq      = { type = "sqs", max_length = 80, charset = "sqs", purpose = "triggeradapterdlq" }
    trigger_adapter_function = { type = "fn", max_length = 64, purpose = "triggeradapter" }
    trigger_adapter_role     = { type = "role", max_length = 64, charset = "iam", purpose = "triggeradapter" }
    trigger_adapter_policy   = { type = "policy", max_length = 128, charset = "iam", purpose = "triggeradapterconsume" }
  }

  default_formats = {
    dashed = "{bu}-{env}-{region}-{purpose}-{type}-{instance}"
    # The body of a path name. The leading segment comes from the spec's prefix,
    # because /aws/lambda/ is mandated by AWS for Lambda log groups rather than
    # being a convention choice.
    path = "{bu}-{env}-{region}-{purpose}-{type}-{instance}"
  }

  # Anchored so a name that is right except for one stray character still fails.
  charsets = {
    dash       = "^[A-Za-z0-9-]+$"
    underscore = "^[A-Za-z0-9_-]+$"
    iam        = "^[A-Za-z0-9+=,.@_-]+$"
    # S3 buckets and private DNS namespaces are DNS-compliant, so lowercase only.
    lowerdot = "^[a-z0-9][a-z0-9.-]*[a-z0-9]$"
    # DynamoDB accepts uppercase, unlike S3.
    ddb    = "^[A-Za-z0-9_.-]+$"
    path   = "^/[A-Za-z0-9._/-]+$"
    sqs    = "^[A-Za-z0-9_-]+(\\.fifo)?$"
    secret = "^[A-Za-z0-9/_+=.@-]+$"
  }

  formats = merge(local.default_formats, var.formats)

  # Per-attribute merge, not a whole-object replace. merge() swaps the entire spec,
  # and because resource_specs carries its own attribute defaults, a partial
  # override like { type = "fn" } would silently reset max_length, charset and
  # purpose — passing the plan and then failing at apply on the real AWS limit.
  specs = {
    for key in distinct(concat(keys(local.default_specs), keys(var.resource_specs))) :
    key => {
      type          = try(var.resource_specs[key].type, null) != null ? var.resource_specs[key].type : try(local.default_specs[key].type, null)
      form          = try(var.resource_specs[key].form, null) != null ? var.resource_specs[key].form : try(local.default_specs[key].form, "dashed")
      max_length    = try(var.resource_specs[key].max_length, null) != null ? var.resource_specs[key].max_length : try(local.default_specs[key].max_length, 255)
      lower         = try(var.resource_specs[key].lower, null) != null ? var.resource_specs[key].lower : try(local.default_specs[key].lower, false)
      charset       = try(var.resource_specs[key].charset, null) != null ? var.resource_specs[key].charset : try(local.default_specs[key].charset, "dash")
      prefix        = try(var.resource_specs[key].prefix, null) != null ? var.resource_specs[key].prefix : try(local.default_specs[key].prefix, "")
      suffix        = try(var.resource_specs[key].suffix, null) != null ? var.resource_specs[key].suffix : try(local.default_specs[key].suffix, "")
      purpose       = try(var.resource_specs[key].purpose, null) != null ? var.resource_specs[key].purpose : try(local.default_specs[key].purpose, null)
      forbid_prefix = try(var.resource_specs[key].forbid_prefix, null) != null ? var.resource_specs[key].forbid_prefix : try(local.default_specs[key].forbid_prefix, null)
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

  bodies = {
    for key, spec in local.specs :
    key => spec.lower ? lower(local.tidied[key]) : local.tidied[key]
  }

  # Deliberately not truncated. Cutting a name to length silently drops the {type}
  # and {instance} segments, so two deployments differing only by instance collapse
  # onto the same name — and for a globally unique type like an S3 bucket the second
  # fails at apply, in a separate state where the duplicate check below cannot see
  # it. Too long is a convention error, so it fails the plan instead. prefix and
  # suffix count against max_length.
  generated = {
    for key, spec in local.specs :
    key => "${spec.prefix}${local.bodies[key]}${spec.suffix}"
  }

  # An explicit override wins over anything generated.
  names = merge(local.generated, var.overrides)

  too_long = [
    for key, value in local.names :
    "${key} = \"${value}\" is ${length(value)} characters, limit is ${local.specs[key].max_length}"
    if contains(keys(local.specs), key) && length(value) > local.specs[key].max_length
  ]

  # Two keys generating the same name is the failure mode this module exists to
  # prevent — it surfaces as a confusing apply error, or silently reuses a resource.
  duplicates = [
    for name, keys in { for key, value in local.names : value => key... } :
    "${name} is generated for more than one resource: ${join(", ", sort(keys))}"
    if length(keys) > 1
  ]

  malformed = concat(
    # Checked on the body rather than the finished name, because a log group name
    # legitimately starts with a separator: /aws/lambda/...
    [
      for key, value in local.bodies :
      "${key} = \"${local.names[key]}\" must not start or end with a separator"
      if contains(keys(local.specs), key) && !contains(keys(var.overrides), key) &&
      length(regexall("^[-_]|[-_]$", value)) > 0
    ],
    [
      for key, value in local.names :
      "${key} = \"${value}\" must match the ${local.specs[key].charset} character set for its resource type (${local.charsets[local.specs[key].charset]})"
      if contains(keys(local.specs), key) &&
      length(regexall(local.charsets[local.specs[key].charset], value)) == 0
    ],
    [
      for key, value in local.names :
      "${key} = \"${value}\" must be lowercase"
      if contains(keys(local.specs), key) && local.specs[key].lower &&
      value != lower(value)
    ],
    # A security group name cannot start with "sg-" — AWS reserves that for the
    # generated group id. Reachable for real: a convention whose first token is
    # "sg" produces exactly this.
    [
      for key, value in local.names :
      "${key} = \"${value}\" must not start with \"${local.specs[key].forbid_prefix}\", which AWS reserves"
      if contains(keys(local.specs), key) && local.specs[key].forbid_prefix != null &&
      startswith(value, local.specs[key].forbid_prefix)
    ]
  )
}
