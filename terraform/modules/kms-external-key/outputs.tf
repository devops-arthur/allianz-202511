output "key_id" {
  description = "KMS key ID."
  value       = aws_kms_external_key.this.id
}

output "key_arn" {
  description = "KMS key ARN. This is the value that ends up on the encrypted resources."
  value       = aws_kms_external_key.this.arn
}

output "key_state" {
  description = "Key state. PendingImport until the key material ceremony has run."
  value       = aws_kms_external_key.this.key_state
}

output "generation" {
  description = "Rotation generation of this key."
  value       = var.generation
}

output "is_current_generation" {
  description = "Whether the service alias points at this generation."
  value       = var.is_current_generation
}

output "generation_alias_name" {
  description = "Immutable alias for this generation, e.g. alias/prod-s3-gen2."
  value       = aws_kms_alias.generation.name
}

output "generation_alias_arn" {
  description = "ARN of the immutable per-generation alias."
  value       = aws_kms_alias.generation.arn
}

output "service_alias_name" {
  description = "Alias workloads reference, e.g. alias/prod-s3. Null when this is not the current generation."
  value       = var.is_current_generation ? one(aws_kms_alias.service[*].name) : null
}

output "service_alias_arn" {
  description = "ARN of the service alias. Workload accounts pass this cross-account ARN to S3/RDS/DynamoDB."
  value       = var.is_current_generation ? one(aws_kms_alias.service[*].arn) : null
}
