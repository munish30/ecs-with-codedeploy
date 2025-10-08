terraform {
  required_providers {
    aws = { 
      source = "hashicorp/aws",
       version = ">=6.14.0"
    }
  }

    backend "s3" {
    bucket         = "tf-states-munish"
    key            = "combined/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region  = "us-east-1"
}