variable "name" {
  description = "Name prefix for backup vault and plan resources."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the backup vault."
  type        = string
}

variable "owner_tag" {
  description = "Value for the Owner tag applied to the vault (e.g. owner@eulerhermes.com)."
  type        = string
}

variable "vault_lock_min_retention_days" {
  type    = number
  default = 30
}

variable "vault_lock_max_retention_days" {
  type    = number
  default = 365
}

# Daily backup rule
variable "daily_schedule" {
  description = "Cron expression for the daily backup window."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "daily_delete_after_days" {
  description = "Days before daily recovery points are deleted."
  type        = number
  default     = 35
}

# Monthly backup rule (longer retention for compliance)
variable "monthly_schedule" {
  description = "Cron expression for the monthly backup."
  type        = string
  default     = "cron(0 5 1 * ? *)"
}

variable "monthly_delete_after_days" {
  description = "Days before monthly recovery points are deleted."
  type        = number
  default     = 365
}

# Cross-region copy
variable "copy_to_region" {
  description = "Secondary region for cross-region backup copies. Null disables cross-region copy."
  type        = string
  default     = null
}

variable "copy_vault_arn" {
  description = "ARN of the destination vault in var.copy_to_region. Required when copy_to_region is set."
  type        = string
  default     = null

  validation {
    condition     = var.copy_to_region == null || var.copy_vault_arn != null
    error_message = "copy_vault_arn must be set when copy_to_region is provided."
  }
}

variable "copy_delete_after_days" {
  description = "Retention for cross-region copies."
  type        = number
  default     = 365
}

# Cross-account copy
variable "cross_account_vault_arn" {
  description = "ARN of the destination vault in the backup/DR account. Null disables cross-account copy."
  type        = string
  default     = null
}

variable "cross_account_delete_after_days" {
  type    = number
  default = 365
}

# Resource selection
variable "backup_tag_key" {
  description = "Tag key used to select resources for backup."
  type        = string
  default     = "ToBackup"
}

variable "backup_tag_value" {
  description = "Tag value used to select resources for backup."
  type        = string
  default     = "true"
}

variable "tags" {
  type    = map(string)
  default = {}
}
