# modules/aws/eks/variables.tf

variable "name" {
  description = "The name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "The AWS region"
  type        = string
}

variable "subnet_ids" {
  description = "A list of subnet IDs for the EKS cluster control plane"
  type        = list(string)
}

variable "fargate_subnet_ids" {
  description = "A list of private subnet IDs for EKS Fargate profiles"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "A list of security group IDs for the EKS cluster"
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Indicates whether or not the API server endpoint is private"
  type        = bool

}

variable "endpoint_public_access" {
  description = "Indicates whether or not the API server endpoint is public. The private endpoint is always enabled; see agent/aws/eks/NETWORKING.md."
  type        = bool
}

variable "public_access_cidrs" {
  description = "A list of CIDR blocks that are allowed to access the API server endpoint"
  type        = list(string)
}

variable "random_string_salt" {
  description = "A random string to ensure unique resource names"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
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

variable "namespace" {
  description = "Kubernetes namespace the runner is installed into. The IRSA role trusts service accounts in this namespace only."
  type        = string
  default     = "matillion"
}

variable "service_account_name" {
  description = "Runner service account name. Must match serviceAccount.name in the Helm values; the chart default is matillion-runner-sa."
  type        = string
  default     = "matillion-runner-sa"
}

variable "script_runner_service_account_name" {
  description = "Script runner service account name. Must match the name the chart renders, which is scriptRunner.serviceAccount.name or, when empty, <fullname>-script-runner-sa. For `helm install matillion-runner` the chart renders matillion-runner-script-runner-sa."
  type        = string
  default     = "matillion-runner-script-runner-sa"
}

variable "authentication_mode" {
  description = <<-EOT
    Cluster authentication mode. API_AND_CONFIG_MAP makes EKS access entries usable
    alongside the aws-auth ConfigMap. AWS allows CONFIG_MAP -> API_AND_CONFIG_MAP -> API
    and does not allow moving back, so lowering this value on an existing cluster fails.
  EOT
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["CONFIG_MAP", "API_AND_CONFIG_MAP", "API"], var.authentication_mode)
    error_message = "authentication_mode must be CONFIG_MAP, API_AND_CONFIG_MAP or API."
  }
}

variable "additional_admin_principal_arns" {
  description = "IAM role or user ARNs granted cluster-admin through EKS access entries. Requires authentication_mode other than CONFIG_MAP."
  type        = list(string)
  default     = []
}
