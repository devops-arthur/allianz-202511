output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution serving api.allianz-trade.com."
  value       = module.cloudfront.distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = module.cloudfront.domain_name
}

output "cloudfront_waf_arn" {
  description = "ARN of the CloudFront-scope WAFv2 web ACL."
  value       = module.waf_cloudfront.web_acl_arn
}

output "public_api_ids" {
  description = "REST API ID per team."
  value       = { for k, v in module.public_api : k => v.api_id }
}

output "public_api_invoke_urls" {
  description = "Default invoke URL per team (before CloudFront; only reachable via CloudFront due to resource policy)."
  value       = { for k, v in module.public_api : k => v.invoke_url }
}

output "public_api_custom_domains" {
  description = "Custom domain regional DNS names to set as CloudFront origins."
  value       = { for k, v in module.public_api : k => v.custom_domain_regional_domain_name }
}

output "regional_waf_arns" {
  description = "ARN of the regional WAFv2 web ACL per team."
  value       = { for k, v in module.waf_regional : k => v.web_acl_arn }
}

output "public_api_origin_verify_secret_arns" {
  description = "ARN of the Secrets Manager secret holding the origin-verify header value per team."
  value       = { for k, v in module.public_api : k => v.origin_verify_secret_arn }
}

output "private_api_ids" {
  description = "REST API ID per internal team."
  value       = { for k, v in module.private_api : k => v.api_id }
}

output "private_api_invoke_urls" {
  description = "Invoke URLs of private APIs (VPC-only)."
  value       = { for k, v in module.private_api : k => v.invoke_url }
}

output "private_api_vpc_endpoint_ids" {
  description = "VPC Interface Endpoint ID per internal team."
  value       = { for k, v in module.private_api : k => v.vpc_endpoint_id }
}

output "access_log_group_names" {
  description = "CloudWatch log group names for API Gateway access logs per team."
  value = merge(
    { for k, v in module.public_api : "${k}-public" => v.access_log_group_name },
    { for k, v in module.private_api : "${k}-private" => v.access_log_group_name },
  )
}
