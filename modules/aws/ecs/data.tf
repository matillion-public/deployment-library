data "aws_caller_identity" "this" {}

data "aws_s3_bucket" "this" {
  count  = var.create_bucket != true ? 1 : 0
  bucket = lookup(var.resource_names, "staging_bucket", join("-", [var.name, "stagging-bucket"]))
}
