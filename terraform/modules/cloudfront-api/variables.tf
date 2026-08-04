variable "domain_name" {
  description = "Primary domain name for the CloudFront distribution (e.g. api.allianz-trade.com)."
  type        = string
}

variable "comment" {
  description = "Comment attached to the CloudFront distribution."
  type        = string
  default     = "Allianz-Trade API gateway CloudFront distribution"
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for the domain. Required for HTTPS."
  type        = string
}

variable "web_acl_arn" {
  description = "ARN of the WAFv2 web ACL (CLOUDFRONT scope) to associate with this distribution."
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "api_origins" {
  description = <<-EOT
    Map of origin ID -> origin configuration. Each entry represents one API team's Regional
    API Gateway custom domain. The origin_verify_secret is injected as a custom header.
  EOT
  type = map(object({
    domain_name           = string
    origin_verify_secret  = string
  }))
}

variable "default_origin_id" {
  description = "Key in var.api_origins to use as the default cache behaviour target."
  type        = string
}

variable "path_behaviors" {
  description = <<-EOT
    Ordered list of path-based cache behaviours. Each entry routes a path pattern to
    a specific origin (team API). Evaluated in order before the default behaviour.
  EOT
  type = list(object({
    path_pattern             = string
    origin_id                = string
    cache_policy_id          = optional(string)
    origin_request_policy_id = optional(string)
  }))
  default = []
}

variable "cache_policy_id" {
  description = "Default CloudFront cache policy ID. Use the AWS managed CachingDisabled policy for APIs."
  type        = string
  # AWS managed CachingDisabled policy
  default = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

variable "origin_request_policy_id" {
  description = "Default CloudFront origin request policy ID. Use AllViewerExceptHostHeader for API Gateway."
  type        = string
  # AWS managed AllViewerExceptHostHeader
  default = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

variable "origin_shield_region" {
  description = "Enable CloudFront Origin Shield in this AWS region. Null disables Origin Shield."
  type        = string
  default     = null
}

variable "viewer_request_function_arn" {
  description = "ARN of a CloudFront Function to run at viewer-request (e.g. for header validation or rewriting)."
  type        = string
  default     = null
}

variable "geo_restriction_type" {
  description = "Geo restriction type: whitelist or blacklist. Only used when geo_restriction_locations is non-empty."
  type        = string
  default     = "blacklist"
}

variable "geo_restriction_locations" {
  description = "ISO 3166-1 alpha-2 country codes to restrict. Empty list disables geo restrictions at CloudFront."
  type        = list(string)
  default     = []
}

variable "access_log_bucket" {
  description = "S3 bucket domain name (not ARN) for CloudFront access logs. Null disables logging."
  type        = string
  default     = null
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID for the domain. When set, an alias A record is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
