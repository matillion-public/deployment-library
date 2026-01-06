variable "use_existing_vpc" {
  type = bool
}

variable "existing_vpc_id" {
  type = string
}
variable "name" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "random_string_salt" {
  type = string
}

variable "use_existing_subnet" {
  type = bool
  default = false
}