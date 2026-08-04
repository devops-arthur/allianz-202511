output "api_id" {
  description = "REST API ID."
  value       = aws_api_gateway_rest_api.this.id
}

output "api_arn" {
  description = "REST API ARN."
  value       = aws_api_gateway_rest_api.this.arn
}

output "root_resource_id" {
  description = "Root resource ID — use this as parent_id for your first resource."
  value       = aws_api_gateway_rest_api.this.root_resource_id
}

output "stage_name" {
  description = "Stage name."
  value       = aws_api_gateway_stage.this.stage_name
}

output "stage_arn" {
  description = "Stage ARN — used for WAFv2 association."
  value       = aws_api_gateway_stage.this.arn
}

output "invoke_url" {
  description = "Default invoke URL (before custom domain)."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "custom_domain_regional_domain_name" {
  description = "Regional domain name of the custom domain — use as CloudFront origin DNS name."
  value       = var.custom_domain_name != null ? aws_api_gateway_domain_name.this[0].regional_domain_name : null
}

output "access_log_group_name" {
  description = "CloudWatch log group name for API access logs."
  value       = aws_cloudwatch_log_group.access_logs.name
}

output "origin_verify_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the CloudFront origin-verify header value."
  value       = aws_secretsmanager_secret.origin_verify.arn
}
