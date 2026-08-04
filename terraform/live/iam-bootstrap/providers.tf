terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Default provider — management/tooling account (assumed via IAM Identity Center or OIDC).
# Used only to create the cicd-bootstrap role in each target account.
provider "aws" {
  region = var.region
  default_tags { tags = var.default_tags }
}

# Aliased providers assume the bootstrap role Terraform just created in each account.
# The role ARNs are computed in main.tf locals so there is no manual input required.

provider "aws" {
  alias  = "account_0"
  region = var.region
  assume_role { role_arn = local.bootstrap_role_arns[0] }
  default_tags { tags = var.default_tags }
}

provider "aws" {
  alias  = "account_1"
  region = var.region
  assume_role { role_arn = local.bootstrap_role_arns[1] }
  default_tags { tags = var.default_tags }
}
