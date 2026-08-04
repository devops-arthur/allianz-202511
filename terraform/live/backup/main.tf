module "backup_dev" {
  source    = "../../modules/backup-policy"
  providers = { aws = aws.dev }

  name        = "dev"
  kms_key_arn = var.kms_key_arns["dev"]
  owner_tag   = var.owner_tag

  copy_to_region          = var.copy_to_region
  copy_vault_arn          = lookup(var.copy_vault_arns, "dev", null)
  cross_account_vault_arn = lookup(var.cross_account_vault_arns, "dev", null)

  tags = { Environment = "dev" }
}

module "backup_int" {
  source    = "../../modules/backup-policy"
  providers = { aws = aws.int }

  name        = "int"
  kms_key_arn = var.kms_key_arns["int"]
  owner_tag   = var.owner_tag

  copy_to_region          = var.copy_to_region
  copy_vault_arn          = lookup(var.copy_vault_arns, "int", null)
  cross_account_vault_arn = lookup(var.cross_account_vault_arns, "int", null)

  tags = { Environment = "int" }
}

module "backup_prod" {
  source    = "../../modules/backup-policy"
  providers = { aws = aws.prod }

  name        = "prod"
  kms_key_arn = var.kms_key_arns["prod"]
  owner_tag   = var.owner_tag

  # Prod: tighter retention and mandatory cross-region + cross-account copies
  daily_delete_after_days   = 35
  monthly_delete_after_days = 365
  copy_to_region            = var.copy_to_region
  copy_vault_arn            = lookup(var.copy_vault_arns, "prod", null)
  cross_account_vault_arn   = lookup(var.cross_account_vault_arns, "prod", null)

  tags = { Environment = "prod" }
}
