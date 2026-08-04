# Default provider — primary region (eu-central-1) for regional resources.
provider "aws" {
  region = var.region

  assume_role {
    role_arn     = var.terraform_execution_role_arn
    session_name = "terraform-api-platform"
  }

  default_tags {
    tags = var.default_tags
  }
}

# CloudFront WAFv2 web ACLs must be created in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  assume_role {
    role_arn     = var.terraform_execution_role_arn
    session_name = "terraform-api-platform-waf-global"
  }

  default_tags {
    tags = var.default_tags
  }
}
