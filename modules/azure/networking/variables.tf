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