# AWS S3 Backend State Management Module
# Creates S3 bucket and DynamoDB table for Terraform state management

locals {
  bucket_name     = lookup(var.resource_names, "state_bucket", "${var.account_id}-terraform-states")
  lock_table_name = lookup(var.resource_names, "state_lock_table", "${var.account_id}-terraform-locks")
}

# S3 bucket for storing Terraform state
resource "aws_s3_bucket" "terraform_state" {
  # The backend's bucket must match this exactly — it is rendered from the
  # backend_config output rather than rebuilt from account_id, so the two cannot
  # drift. Changing it on a deployed platform is a state migration, not a rename.
  bucket = local.bucket_name

  tags = {
    Name        = "Terraform State Bucket"
    Purpose     = "TerraformState"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Holds every state file for the deployment, and bucket is force-new. Renaming it
  # through resource_names would otherwise plan a destroy and recreate of the
  # backend's own storage. Remove this block only for a deliberate teardown.
  lifecycle {
    prevent_destroy = true
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform Lock Table"
    Purpose     = "TerraformLocking"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # name is force-new here too, and losing the lock table mid-migration is how two
  # applies end up racing the same state. Remove this block only for a deliberate
  # teardown.
  lifecycle {
    prevent_destroy = true
  }
}

# S3 bucket policy to allow access from deployment roles
resource "aws_s3_bucket_policy" "terraform_state_policy" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTerraformAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_role_arns
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })
}