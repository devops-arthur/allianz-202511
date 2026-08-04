variable "region" {
  type    = string
  default = "us-east-1"
}

# Map of account label -> account ID for every account that needs a Terraform execution role.
# Example: { security = "111111111111", workload-dev = "222222222222" }
variable "target_accounts" {
  description = "Label -> AWS account ID for each account that needs a Terraform execution role."
  type        = map(string)
  validation {
    condition     = alltrue([for id in values(var.target_accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "Each value must be a 12-digit AWS account ID."
  }
}

# ARN of the IAM OIDC provider that already exists in each target account.
# If you use a centralised OIDC provider, supply the same ARN for all accounts.
variable "oidc_provider_arn_by_account" {
  description = "Account label -> OIDC provider ARN in that account."
  type        = map(string)
}

variable "oidc_subjects" {
  description = "OIDC subject claims permitted to assume the Terraform execution role."
  type        = list(string)
  # GitHub example: ["repo:my-org/infra:ref:refs/heads/main"]
}

variable "bootstrap_role_name" {
  description = "Name of the short-lived bootstrap role created in each target account."
  type        = string
  default     = "cicd-bootstrap"
}

variable "terraform_role_name" {
  type    = string
  default = "terraform-execution"
}

variable "default_tags" {
  type = map(string)
  default = {
    ManagedBy = "terraform"
    Purpose   = "ci-terraform-execution"
  }
}
