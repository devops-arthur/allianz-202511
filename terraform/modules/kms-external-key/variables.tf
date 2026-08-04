variable "environment" {
  description = "Environment the key belongs to (dev, int, prod). Part of the alias name."
  type        = string
}

variable "service" {
  description = "Service the key is dedicated to (s3, rds, ddb). Part of the alias name."
  type        = string
}

variable "generation" {
  description = <<-EOT
    Rotation generation of this key. Keys with imported (BYOK/EXTERNAL) key material cannot be
    rotated in place, so a rotation creates a new generation and re-points the service alias.
    Generation 1 is the initial key.
  EOT
  type        = number

  validation {
    condition     = var.generation >= 1
    error_message = "generation must be >= 1."
  }
}

variable "is_current_generation" {
  description = "Whether this generation is the one the service alias (alias/<env>-<service>) points to."
  type        = bool
  default     = false
}

variable "enabled" {
  description = <<-EOT
    Desired key state. Keep false until the key material ceremony has completed: a KMS key created
    with origin EXTERNAL and no material is in PendingImport and cannot be enabled. The import
    pipeline enables the key, and 'enabled' is in ignore_changes so Terraform does not fight it.
  EOT
  type        = bool
  default     = false
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes. Keep high for regulated workloads."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "key_material_valid_to" {
  description = <<-EOT
    Optional RFC3339 expiration for the imported key material. When set, KMS deletes the material at
    that time and the key becomes unusable, which enforces the rotation cadence but is also an
    availability risk - only set it if the re-import/rotation pipeline is proven.
  EOT
  type        = string
  default     = null
}

variable "multi_region" {
  description = "Create a multi-region key. Multi-region + imported material requires importing the same material into every replica."
  type        = bool
  default     = false
}

variable "consumer_account_ids" {
  description = "Workload account IDs (dev/int/prod) allowed to use this key through the AWS service in var.service."
  type        = list(string)

  validation {
    condition     = length(var.consumer_account_ids) > 0
    error_message = "At least one consumer account must be granted usage."
  }
}

variable "consumer_principal_arns" {
  description = <<-EOT
    Optional tightening of the consumer statement. When non-empty, only these IAM principals (roles in
    the consumer accounts) may use the key, instead of delegating to the whole account via
    kms:CallerAccount. Use for prod.
  EOT
  type        = list(string)
  default     = []
}

variable "key_admin_role_arns" {
  description = "Roles in the security account that administer the key lifecycle. They get no data-plane (Encrypt/Decrypt) permissions."
  type        = list(string)
}

variable "key_material_importer_role_arns" {
  description = "Roles allowed to run the key material ceremony (GetParametersForImport / ImportKeyMaterial)."
  type        = list(string)
  default     = []
}

variable "break_glass_role_arns" {
  description = "Only these roles may schedule key deletion or delete imported key material. Everyone else is explicitly denied."
  type        = list(string)
  default     = []
}

variable "auditor_role_arns" {
  description = "Read-only roles (security tooling, auditors) allowed to describe the key and list its grants/tags."
  type        = list(string)
  default     = []
}

variable "compliance_reader_arns" {
  description = <<-EOT
    Principals in the workload accounts that must resolve the service alias to the current key ARN
    (the AWS Config custom rule Lambda roles). They only get kms:DescribeKey.
  EOT
  type        = list(string)
  default     = []
}

variable "via_service_principals" {
  description = "kms:ViaService values that scope data-plane usage to the owning AWS service. Defaults are derived from var.service and the current region."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the key and its aliases."
  type        = map(string)
  default     = {}
}
