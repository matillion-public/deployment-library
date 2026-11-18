###############################################################################
# Amazon MSK -> Maia Foundation pipeline-execution Lambda adapter
#
# Optional add-on. Consumes records from Amazon MSK topics and triggers a Maia
# Foundation pipeline per record via the Maia Foundation pipeline-execution API. The
# handler is the same arm64 container image as modules/aws/lambda/sqs-dpc-adapter,
# told its source through MATILLION_AWS_EVENT_SOURCE; this module only provisions
# the surrounding AWS resources.
#
# The cluster, its topics, the SCRAM secret and the failure topic are always
# bring-your-own. The project-mapping table can be created or referenced.
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names created by this module."
  type        = string
  default     = "matillion-maia-msk-adapter"
}

variable "aws_region" {
  description = "AWS region the adapter runs in."
  type        = string
}

variable "image_uri" {
  description = "Private ECR image URI (arm64) for the adapter Lambda, in the same region as the function. The image must include the MSK source. Lambda will not run an ECR Public image: copy public.ecr.aws/matillion/maia-queue-adapter:<version>-arm64 into your own ECR first (see the maia-queueing-adapter README)."
  type        = string
}

# ---------------------------------------------------------------------------
# MSK source (always bring-your-own).
# ---------------------------------------------------------------------------
variable "cluster_arn" {
  description = "ARN of the MSK cluster."
  type        = string
}

variable "topics" {
  description = "Topics whose records trigger pipelines. Each gets its own event source mapping, since a Kafka mapping reads exactly one topic; all of them share one poller group, which takes at most 100."
  type        = list(string)

  validation {
    condition     = length(var.topics) >= 1 && length(var.topics) <= 100
    error_message = "topics must name between 1 and 100 topics; one poller group takes at most 100 mappings."
  }

  validation {
    condition     = length(var.topics) == length(distinct(var.topics))
    error_message = "topics must not repeat a topic; a duplicate makes one event source mapping but is still counted against the 100-mapping and poller limits."
  }
}

variable "topic_routes" {
  description = "Topics whose producers send their own payload rather than the adapter's message envelope, each mapped to the pipeline its records trigger. The record value reaches that pipeline base64-encoded in the scalar variable payload_variable, alongside kafkaTopic, kafkaPartition and kafkaOffset. A topic left out must carry the envelope."
  type = map(object({
    project          = string
    environment      = string
    pipeline         = string
    payload_variable = string
  }))
  default = {}

  validation {
    condition     = alltrue([for topic in keys(var.topic_routes) : contains(var.topics, topic)])
    error_message = "Every topic_routes key must also be in topics, or no mapping reads it."
  }

  validation {
    condition = alltrue([for route in values(var.topic_routes) : !contains(
      ["kafkaTopic", "kafkaPartition", "kafkaOffset"], route.payload_variable
    )])
    error_message = "payload_variable must not be kafkaTopic, kafkaPartition or kafkaOffset; the adapter sets those itself."
  }

  validation {
    condition     = alltrue([for route in values(var.topic_routes) : trimspace(route.payload_variable) != ""])
    error_message = "payload_variable must name a pipeline variable; an empty name would drop the record value."
  }

  validation {
    condition = alltrue([for route in values(var.topic_routes) :
      trimspace(route.project) != "" && trimspace(route.environment) != "" && trimspace(route.pipeline) != ""
    ])
    error_message = "project, environment and pipeline must each be set; the adapter refuses an empty one at cold start, so a blank value fails every record after apply rather than at plan."
  }

  validation {
    condition     = length(jsonencode(var.topic_routes)) <= 3072
    error_message = "topic_routes is too large: Lambda limits all of a function's environment variables to 4 KB together, and the routes are one of them. Keep the encoded routes under about 3 KB (roughly 20 to 25 routes of the documented size), or split the topics across adapters."
  }
}

variable "scram_secret_arn" {
  description = "Secrets Manager secret holding the SASL/SCRAM-512 username and password. MSK requires its name to start with AmazonMSK_."
  type        = string
}

variable "scram_kms_key_arn" {
  description = "Customer managed KMS key that encrypts the SCRAM secret; MSK does not accept the AWS managed key."
  type        = string
}

variable "failure_topic" {
  description = "Topic on the same cluster that receives a record, with its content, once its retries are spent. It must already exist."
  type        = string

  validation {
    condition     = !contains(var.topics, var.failure_topic)
    error_message = "failure_topic must not be one of topics, or failed records would be read back and triggered again."
  }
}

variable "starting_position" {
  description = "Where a new consumer group starts reading. LATEST, because TRIM_HORIZON would trigger a pipeline for every record the topic still retains."
  type        = string
  default     = "LATEST"

  validation {
    condition     = contains(["LATEST", "TRIM_HORIZON"], var.starting_position)
    error_message = "starting_position must be \"LATEST\" or \"TRIM_HORIZON\"."
  }
}

variable "batch_size" {
  description = "Maximum records per invocation. At 1, a record that fails only holds back itself. Larger batches raise per-partition throughput, but a failed record carries the records behind it in the same batch into failure_topic unrun, and the batch has to fit inside the function timeout."
  type        = number
  default     = 1

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 10000
    error_message = "batch_size must be between 1 and 10000."
  }
}

variable "minimum_pollers" {
  description = "Event pollers each topic's mapping keeps running at all times. The mappings share the poller group's event poller units, which are what is billed."
  type        = number
  default     = 1

  validation {
    condition     = var.minimum_pollers >= 1 && var.minimum_pollers <= 200
    error_message = "minimum_pollers must be between 1 and 200."
  }
}

variable "maximum_pollers" {
  description = "Event pollers each topic's mapping can scale up to under load. Concurrency is still capped at one invocation per partition."
  type        = number
  default     = 10

  validation {
    condition     = var.maximum_pollers >= var.minimum_pollers && var.maximum_pollers * length(var.topics) <= 2000
    error_message = "maximum_pollers must not be below minimum_pollers, and maximum_pollers times the number of topics must not exceed 2000, the poller group's limit."
  }
}

variable "maximum_retry_attempts" {
  description = "Retries for a failed record before it goes to failure_topic."
  type        = number
  default     = 3

  validation {
    condition     = var.maximum_retry_attempts >= 0 && var.maximum_retry_attempts <= 10000
    error_message = "maximum_retry_attempts must be between 0 and 10000; -1 (retry until the record expires) would never reach failure_topic."
  }
}

# ---------------------------------------------------------------------------
# Project-mapping table: create or BYO.
# ---------------------------------------------------------------------------
variable "create_mapping_table" {
  description = "If true, create the DynamoDB project-mapping table. If false, reference an existing one via existing_mapping_table_name/arn."
  type        = bool
  default     = true
}

variable "mapping_table_name" {
  description = "Name of the project-mapping DynamoDB table to create (when create_mapping_table = true)."
  type        = string
  default     = "matillion-msk-project-mappings"
}

variable "existing_mapping_table_name" {
  description = "Name of an existing project-mapping DynamoDB table (when create_mapping_table = false)."
  type        = string
  default     = ""
}

variable "existing_mapping_table_arn" {
  description = "ARN of an existing project-mapping DynamoDB table (when create_mapping_table = false). The '/index/*' GSI ARN is granted automatically."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Maia Foundation API / OAuth (secret is always BYO).
# ---------------------------------------------------------------------------
variable "secret_name" {
  description = "Name of the pre-existing Secrets Manager secret holding {client_id, client_secret} for Maia Foundation OAuth."
  type        = string
}

variable "matillion_api_url" {
  description = "Maia Foundation pipeline-execution API base URL."
  type        = string
  default     = "https://eu1.api.matillion.com/dpc/v1"
}

variable "matillion_token_url" {
  description = "Maia Foundation OAuth token endpoint."
  type        = string
  default     = "https://id.core.matillion.com/oauth/dpc/token"
}

# ---------------------------------------------------------------------------
# Lambda runtime tuning.
# ---------------------------------------------------------------------------
variable "memory_size" {
  description = "Lambda memory (MB)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Lambda timeout (seconds)."
  type        = number
  default     = 60
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions for the Lambda. -1 leaves it unreserved. One cap is shared by every topic, so if set it must be at least the total partition count across topics, or a burst is throttled."
  type        = number
  default     = -1
}

variable "log_level" {
  description = "Application log level (MATILLION_LOG_LEVEL)."
  type        = string
  default     = "INFO"
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray active tracing."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention (days) for the Lambda log group."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Observability.
# ---------------------------------------------------------------------------
variable "create_alarms" {
  description = "Create the SNS topic + CloudWatch alarms (records reaching the failure topic, Lambda errors/throttles)."
  type        = bool
  default     = true
}

variable "alarm_lambda_error_threshold" {
  description = "Alarm when Lambda errors exceed this count in the evaluation period."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/aws/naming, which builds them from a token
    convention. Any key left out keeps its generated name.
  EOT
  type        = map(string)
  default     = {}
}
