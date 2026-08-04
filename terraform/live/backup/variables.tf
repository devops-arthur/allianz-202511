variable "region" {
  type    = string
  default = "us-east-1"
}

variable "workload_accounts" {
  description = "Environment -> account ID. Must contain dev, int, prod."
  type        = map(string)
  validation {
    condition     = alltrue([for id in values(var.workload_accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "Each value must be a 12-digit AWS account ID."
  }
  validation {
    condition     = alltrue([for k in ["dev", "int", "prod"] : contains(keys(var.workload_accounts), k)])
    error_message = "workload_accounts must contain dev, int, and prod."
  }
}

variable "terraform_execution_role_name" {
  type    = string
  default = "terraform-execution"
}

variable "kms_key_arns" {
  description = "Environment -> KMS key ARN used to encrypt the backup vault in that account."
  type        = map(string)
}

variable "owner_tag" {
  description = "Owner tag value applied to all backup vaults."
  type        = string
  default     = "owner@eulerhermes.com"
}

variable "copy_to_region" {
  description = "Secondary region for cross-region backup copies. Null disables."
  type        = string
  default     = null
}

variable "copy_vault_arns" {
  description = "Environment -> destination vault ARN in var.copy_to_region."
  type        = map(string)
  default     = {}
}

variable "cross_account_vault_arns" {
  description = "Environment -> destination vault ARN in the DR/backup account."
  type        = map(string)
  default     = {}
}

variable "default_tags" {
  type = map(string)
  default = {
    Project   = "backup-policy"
    ManagedBy = "terraform"
  }
}
