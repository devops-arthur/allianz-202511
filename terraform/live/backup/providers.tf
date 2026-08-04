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
  alias  = "dev"
  region = var.region
  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["dev"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-backup-dev"
  }
  default_tags { tags = merge(var.default_tags, { Environment = "dev" }) }
}

provider "aws" {
  alias  = "int"
  region = var.region
  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["int"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-backup-int"
  }
  default_tags { tags = merge(var.default_tags, { Environment = "int" }) }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["prod"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-backup-prod"
  }
  default_tags { tags = merge(var.default_tags, { Environment = "prod" }) }
}
