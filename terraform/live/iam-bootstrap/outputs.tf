output "bootstrap_role_arns" {
  description = "Bootstrap role ARN per account label."
  value       = { for label, role in aws_iam_role.bootstrap : label => role.arn }
}

output "terraform_role_arns" {
  description = "Terraform execution role ARN per account label."
  value = {
    (local.account_labels[0]) = module.terraform_role_account_0.role_arn
    (local.account_labels[1]) = module.terraform_role_account_1.role_arn
  }
}
