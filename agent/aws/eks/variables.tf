resource "random_string" "salt" {
  length  = 8
  numeric = false
  special = false
}

variable "use_existing_vpc" {
  type    = bool
  default = false
}

variable "existing_vpc_id" {
  type    = string
  default = ""
}

variable "cidr_block" {
  type    = string
  default = "172.5.0.0/16"

}

variable "name" {
  type    = string
  default = "matillion-etl"
}

variable "region" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "use_existing_subnet" {
  type    = bool
  default = false
}

variable "existing_subnet_ids" {
  type    = list(string)
  default = []
}

variable "is_private_cluster" {
  type    = bool
  default = true
}

variable "authorized_ip_ranges" {
  type    = list(string)
  default = [""]
}