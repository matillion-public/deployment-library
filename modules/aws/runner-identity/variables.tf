variable "name" {
  type        = string
  description = "Name prefix for this runner's identity resources. Use something that identifies the tenant, e.g. 'grid' or 'retail'."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the EKS cluster (the cluster's identity[0].oidc[0].issuer). An IAM OIDC provider must already exist for this issuer — IRSA silently fails to issue credentials without one."
}

variable "partition" {
  type        = string
  description = "AWS partition. 'aws' for commercial regions, 'aws-us-gov' for GovCloud, 'aws-cn' for China."
  default     = "aws"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace this runner is deployed into"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name for the runner pod. Must match serviceAccount.name in the Helm values exactly — the trust policy names this subject and nothing else."
}

variable "script_runner_service_account_name" {
  type        = string
  description = "Kubernetes service account name for the script runner pod. Empty omits it from the trust policy."
  default     = ""
}

variable "secret_arns" {
  type        = list(string)
  description = "Secrets Manager ARNs this runner may read. The runner cannot read anything not listed here. Read only — a runner consumes credentials and has no reason to be able to overwrite them."
  default     = []
}

variable "s3_bucket_arns" {
  type        = list(string)
  description = "S3 bucket ARNs the runner may use for staging. Object-level access is derived from each bucket ARN."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the IAM role"
  default     = {}
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
