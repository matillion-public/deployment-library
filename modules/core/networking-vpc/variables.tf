variable "cloud" {
  description = "Which cloud this networking config targets. The AWS and GCP composer contracts share this module path; select the active provider here."
  type        = string
  validation {
    condition     = contains(["aws", "gcp"], var.cloud)
    error_message = "cloud must be 'aws' or 'gcp' (Azure uses core/networking-vnet)."
  }
}

variable "deployment_name" {
  description = "Deployment name prefix."
  type        = string
  default     = "matillion-agent"
}

# --- AWS inputs (cloud = aws) ------------------------------------------------
variable "vpc_id" {
  description = "AWS: ID of the existing VPC the agent deploys into."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "AWS: IDs of the existing subnets the agent service uses."
  type        = list(string)
  default     = []
}

# --- GCP inputs (cloud = gcp) ------------------------------------------------
variable "project_id" {
  description = "GCP: project ID."
  type        = string
  default     = ""
}

variable "network" {
  description = "GCP: self-link or name of the existing VPC network."
  type        = string
  default     = ""
}

variable "subnetwork" {
  description = "GCP: self-link or name of the existing subnetwork."
  type        = string
  default     = ""
}

# --- Least-privilege deployer policy ----------------------------------------
variable "create_deployer_policy" {
  description = "Create the least-privilege deployer policy (AWS managed policy) / custom role (GCP)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags/labels applied to created resources."
  type        = map(string)
  default     = {}
}
