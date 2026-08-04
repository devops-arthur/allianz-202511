terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn     = var.terraform_execution_role_arn
    session_name = "terraform-gitlab"
  }

  default_tags { tags = var.default_tags }
}
