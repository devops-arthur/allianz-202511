output "api_id" {
  description = "REST API ID."
  value       = aws_api_gateway_rest_api.this.id
}

output "api_arn" {
  description = "REST API ARN."
  value       = aws_api_gateway_rest_api.this.arn
}

output "root_resource_id" {
  description = "Root resource ID."
  value       = aws_api_gateway_rest_api.this.root_resource_id
}

output "stage_name" {
  description = "Stage name."
  value       = aws_api_gateway_stage.this.stage_name
}

output "invoke_url" {
  description = "Invoke URL (only reachable from within the VPC via the endpoint)."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "vpc_endpoint_id" {
  description = "ID of the execute-api VPC Interface Endpoint."
  value       = aws_vpc_endpoint.execute_api.id
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries of the VPC Interface Endpoint."
  value       = aws_vpc_endpoint.execute_api.dns_entry
}

output "access_log_group_name" {
  description = "CloudWatch log group name for API access logs."
  value       = aws_cloudwatch_log_group.access_logs.name
}
