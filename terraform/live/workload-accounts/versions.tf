terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # Replace with the real backend for the account that manages this state.
  # backend "s3" {
  #   bucket       = "allianz-tfstate-security"
  #   key          = "encryption/workload-accounts/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
