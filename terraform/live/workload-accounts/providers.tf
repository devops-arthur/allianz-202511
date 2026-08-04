# ---------------------------------------------------------------------------
# Provider aliases - one per workload account.
# Terraform assumes the given role in each account so a single root module
# can drive all three environments without juggling separate workspaces.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "dev"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["dev"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-workload-accounts-dev"
  }

  default_tags {
    tags = merge(var.default_tags, { Environment = "dev" })
  }
}

provider "aws" {
  alias  = "int"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["int"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-workload-accounts-int"
  }

  default_tags {
    tags = merge(var.default_tags, { Environment = "int" })
  }
}

provider "aws" {
  alias  = "prod"
  region = var.region

  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_accounts["prod"]}:role/${var.terraform_execution_role_name}"
    session_name = "terraform-workload-accounts-prod"
  }

  default_tags {
    tags = merge(var.default_tags, { Environment = "prod" })
  }
}
