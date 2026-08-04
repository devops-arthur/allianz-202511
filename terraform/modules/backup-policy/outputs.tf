output "vault_arn" {
  description = "ARN of the backup vault."
  value       = aws_backup_vault.main.arn
}

output "vault_name" {
  description = "Name of the backup vault."
  value       = aws_backup_vault.main.name
}

output "plan_id" {
  description = "ID of the backup plan."
  value       = aws_backup_plan.main.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup."
  value       = aws_iam_role.backup.arn
}
