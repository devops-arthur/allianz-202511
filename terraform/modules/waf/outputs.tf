output "web_acl_arn" {
  description = "ARN of the WAFv2 web ACL. Pass to CloudFront (web_acl_id) or API Gateway (aws_wafv2_web_acl_association)."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the WAFv2 web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the WAFv2 web ACL."
  value       = aws_wafv2_web_acl.this.name
}
