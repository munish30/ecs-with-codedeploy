provider "aws" {
  region = "us-east-1"   # Change to your preferred region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "tf-states-munish"   # Change to a globally unique name

  tags = {
    Name        = "Terraform state bucket"
    Environment = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform state lock table"
    Environment = "Terraform"
  }
}