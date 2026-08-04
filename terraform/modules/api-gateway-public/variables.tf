variable "name" {
  description = "Name of the REST API and associated resources."
  type        = string
}

variable "description" {
  description = "Human-readable description of the API."
  type        = string
  default     = "Public Regional API Gateway managed by Terraform"
}

variable "stage_name" {
  description = "API Gateway stage name (e.g. v1, prod)."
  type        = string
  default     = "v1"
}

variable "origin_verify_secret_value" {
  description = <<-EOT
    Shared secret injected by CloudFront as a custom origin header (x-origin-verify).
    The resource policy denies any request that does not carry this value, preventing
    direct access to the regional execute-api endpoint.
    Store this in Secrets Manager and rotate quarterly.
  EOT
  type      = string
  sensitive = true
}

variable "regional_web_acl_arn" {
  description = "ARN of a REGIONAL WAFv2 web ACL to associate with the API Gateway stage. Null disables the association."
  type        = string
  default     = null
}

variable "custom_domain_name" {
  description = "Custom domain name for the API (e.g. payments-api.allianz-trade.com). Null skips domain creation."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the custom domain name. Required when custom_domain_name is set."
  type        = string
  default     = null
}

variable "base_path" {
  description = "Base path mapping on the custom domain. Empty string maps the root."
  type        = string
  default     = ""
}

variable "log_retention_in_days" {
  description = "Retention period for the CloudWatch access log group."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
