output "vault_arns" {
  description = "Backup vault ARN per environment."
  value = {
    dev  = module.backup_dev.vault_arn
    int  = module.backup_int.vault_arn
    prod = module.backup_prod.vault_arn
  }
}
