variable "role_name" {
  description = "Name of the Terraform execution IAM role."
  type        = string
  default     = "terraform-execution"
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (GitHub or GitLab) in this account."
  type        = string
}

variable "oidc_subjects" {
  description = <<-EOT
    List of OIDC subject claims allowed to assume this role.
    GitHub example : ["repo:my-org/my-repo:ref:refs/heads/main"]
    GitLab example : ["project_path:my-group/my-project:ref_type:branch:ref:main"]
  EOT
  type        = list(string)
}

variable "managed_policy_arns" {
  description = "Additional managed policies to attach (e.g. ReadOnlyAccess for plan-only roles)."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline policy JSON granting Terraform the permissions it needs."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (900–43200)."
  type        = number
  default     = 3600
}

variable "tags" {
  type    = map(string)
  default = {}
}
