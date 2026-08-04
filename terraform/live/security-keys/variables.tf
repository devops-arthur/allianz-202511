variable "region" {
  description = "Region the keys live in."
  type        = string
  default     = "us-east-1"
}

variable "terraform_execution_role_arn" {
  description = "Role in the security account Terraform assumes to manage the keys."
  type        = string
}

variable "workload_accounts" {
  description = "Environment name -> workload account ID. One set of keys is created per environment."
  type        = map(string)

  validation {
    condition     = alltrue([for id in values(var.workload_accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "Each workload account must be a 12-digit AWS account ID."
  }
}

variable "services" {
  description = "Services that get their own key per environment. Drives the alias names (alias/<env>-<service>)."
  type        = list(string)
  default     = ["s3", "rds", "ddb"]
}

variable "key_rotation_state" {
  description = <<-EOT
    Rotation state per key, keyed by "<environment>-<service>" (e.g. "prod-s3").

      current_generation   - generation the service alias points to. Bump it to rotate.
      retained_generations - previous generations that must stay enabled so existing ciphertext
                             (old S3 objects, snapshots, backups) can still be decrypted.

    Keys not listed here default to generation 1 with nothing retained.
  EOT
  type = map(object({
    current_generation   = number
    retained_generations = optional(list(number), [])
  }))
  default = {}
}

variable "key_material_valid_to" {
  description = <<-EOT
    Optional RFC3339 key material expiration per key, keyed by "<environment>-<service>". Leave empty
    to import material without expiration and drive rotation from the pipeline instead - expiring
    material makes every ciphertext undecryptable the moment it lapses.
  EOT
  type        = map(string)
  default     = {}
}

variable "key_admin_role_arns" {
  description = "Security-account roles that administer the key lifecycle (no Encrypt/Decrypt)."
  type        = list(string)

  validation {
    condition     = length(var.key_admin_role_arns) > 0
    error_message = "At least one key administrator role is required, otherwise the key policy locks everyone out."
  }
}

variable "key_material_importer_role_arns" {
  description = "Roles allowed to run the HSM -> KMS key material ceremony."
  type        = list(string)
  default     = []
}

variable "break_glass_role_arns" {
  description = "Roles allowed to delete key material or schedule key deletion. Everything else is denied."
  type        = list(string)
  default     = []
}

variable "auditor_role_arns" {
  description = "Read-only roles for security tooling and auditors."
  type        = list(string)
  default     = []
}

variable "rotation_compliance_role_name" {
  description = <<-EOT
    Name of the AWS Config custom-rule Lambda execution role deployed in every workload account.
    Granted kms:DescribeKey so it can resolve alias/<env>-<service> to the current key ARN.
  EOT
  type        = string
  default     = "config-rule-kms-rotation-compliance"
}

variable "restrict_prod_to_principals" {
  description = <<-EOT
    Environments whose keys are restricted to explicit principal ARNs instead of delegating to the
    whole workload account. Requires an entry in var.environment_principal_arns.
  EOT
  type        = list(string)
  default     = []
}

variable "environment_principal_arns" {
  description = "Environment -> explicit list of consumer principal ARNs, used for environments listed in var.restrict_prod_to_principals."
  type        = map(list(string))
  default     = {}
}

variable "deletion_window_in_days" {
  description = "Waiting period for scheduled key deletion."
  type        = number
  default     = 30
}

variable "default_tags" {
  description = "Tags applied to every resource in this root module."
  type        = map(string)
  default = {
    Project   = "encryption-management"
    ManagedBy = "terraform"
  }
}
