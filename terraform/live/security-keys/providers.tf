provider "aws" {
  region = var.region

  assume_role {
    role_arn     = var.terraform_execution_role_arn
    session_name = "terraform-security-keys"
  }

  default_tags {
    tags = var.default_tags
  }
}
