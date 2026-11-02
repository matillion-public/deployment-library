variable "name" {
  type        = string
  description = "The runner's name. It names the runner's namespace, service accounts, IAM roles and secret prefix, so no two runners in a cluster may share one."

  validation {
    # The IAM role adds "-runner-role", and role names are capped at 64 characters.
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and use only lowercase letters, digits and hyphens, up to 40 characters."
  }

  validation {
    # The name is the runner's namespace, and Kubernetes keeps these for itself.
    condition     = var.name != "default" && !can(regex("^kube-", var.name))
    error_message = "name can't be \"default\" or start with \"kube-\": it becomes the runner's namespace, and those are Kubernetes' own."
  }

  validation {
    # Runner "x"'s script runner is named "x-scripts", so a runner of that name would
    # take its IAM role.
    condition     = !can(regex("-scripts$", var.name))
    error_message = "name can't end in \"-scripts\": that is how another runner's script runner is named."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the cluster."
}

variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to deploy the runner into. Its IAM OIDC provider must already exist (eksctl utils associate-iam-oidc-provider --cluster <name> --approve)."
}

variable "s3_bucket_arns" {
  type        = list(string)
  description = "S3 buckets the runner may read and write, for staging and for loading data. The default is every bucket, as the other runner templates allow; list the business unit's own buckets to keep runners out of each other's data."
  default     = ["arn:aws:s3:::*"]
}

variable "fargate_subnet_ids" {
  type        = list(string)
  description = "Private subnets for a Fargate profile that runs the runner's namespace. Set these when the cluster runs pods on Fargate; on a cluster with node groups, leave empty."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags for every resource this creates."
  default     = {}
}
