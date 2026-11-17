variable "name" {
  type        = string
  description = <<-EOT
    The runner's name. It is the namespace Helm installs the runner into, and names
    the service accounts the chart creates there, as well as the managed identities
    and Key Vault this creates. Two runners in one cluster must never share a name,
    even with different resource groups: each identity trusts the subject
    system:serviceaccount:<name>:<name>-sa, so a second runner with the same name
    could use the first one's identity and read its secrets. It can't be default or
    start with kube-, which Kubernetes keeps for itself, or end in -scripts, because
    the script runner's identity of a runner called "finance" is named
    "finance-scripts", and would collide with a runner of that name.
  EOT

  validation {
    # Matches runner/aws/eks-existing-cluster, so a runner's name works on either
    # cloud. The Key Vault takes the first 17 characters, plus a random suffix.
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and use only lowercase letters, digits and hyphens, up to 40 characters."
  }

  validation {
    condition     = var.name != "default" && !can(regex("^kube-", var.name))
    error_message = "name is the runner's namespace, so it can't be default or start with kube-: Kubernetes keeps those for itself."
  }

  validation {
    condition     = !can(regex("-scripts$", var.name))
    error_message = "name can't end in -scripts: the script runner identity of the runner without that ending has the same name."
  }
}

variable "azure_subscription_id" {
  type        = string
  description = "Subscription of the cluster. The runner's identities and Key Vault are created in it too."
}

variable "cluster_name" {
  type        = string
  description = <<-EOT
    Name of the existing AKS cluster to deploy the runner into. It must have its OIDC
    issuer and workload identity enabled (az aks update --enable-oidc-issuer
    --enable-workload-identity). The plan checks the OIDC issuer. It can't check
    workload identity: without it the federated credentials apply cleanly, but the
    webhook that hands pods their token never runs, and the runner fails at start-up
    with an Azure identity or token error.
  EOT
}

variable "cluster_resource_group_name" {
  type        = string
  description = "Resource group of the existing AKS cluster."
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group for the runner's managed identities and Key Vault. Defaults to the cluster's; set it to keep each business unit's resources in its own group."
  default     = null
}

variable "storage_account_ids" {
  type        = list(string)
  description = "Resource IDs of the storage accounts the runner and its script runner may use, for staging and for loading data. The default is none: the other Azure templates grant only the staging account they create, never every account, and this one creates none. List the business unit's own accounts."
  default     = []
}

variable "grant_storage_account_keys" {
  type        = bool
  description = "Give the runner, not the script runner, Reader and Data Access on each of storage_account_ids, so it can find the accounts through Azure Resource Manager and read their keys. The runner signs the SAS for Snowflake and Databricks loads from Azure staging with a key. Keys cover the whole account, queues, tables and files included, and last until rotated. Set false to give blob access only, at the cost of those loads and the storage account picker."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags for every resource this creates."
  default     = {}
}
