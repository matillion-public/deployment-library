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