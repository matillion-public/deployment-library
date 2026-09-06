variable "name" {
  type = string
}

variable "random_string_salt" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "vnet_address_space" {
  type        = string
  description = "Address space for the VNet (e.g. 10.0.0.0/16)"
  default     = "10.0.0.0/16"
}

variable "subnet_configs" {
  type = list(object({
    newbits = number
    netnum  = number
    delegation = optional(object({
      name = string
      service_delegation = object({
        name    = string
        actions = list(string)
      })
    }))
  }))
  description = "List of subnet configurations using cidrsubnet(vnet_address_space, newbits, netnum). Defaults to two /24 subnets for AKS."
  default = [
    { newbits = 8, netnum = 1, delegation = null },
    { newbits = 8, netnum = 2, delegation = null }
  ]
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

variable "nat_gateway_idle_timeout" {
  type    = number
  default = 10

  validation {
    condition     = var.nat_gateway_idle_timeout >= 4 && var.nat_gateway_idle_timeout <= 120
    error_message = "NAT Gateway idle timeout must be between 4 and 120 minutes."
  }
}

variable "service_endpoints" {
  description = <<-EOT
    Service endpoints enabled on each subnet. Key Vault and Storage are needed
    wherever those resources restrict access to selected networks: the queue adapter
    reads its OAuth secret from Key Vault and its project mapping from Table Storage.

    Add "Microsoft.ServiceBus" for the servicebus queue backend, and
    "Microsoft.ContainerRegistry" where images come from an ACR with restricted
    network access. Enabling an endpoint here is only half of the arrangement — the
    target resource's own network rules must also allow this subnet.
  EOT
  type        = list(string)
  default     = ["Microsoft.Storage", "Microsoft.KeyVault"]
}
