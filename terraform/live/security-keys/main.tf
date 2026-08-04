data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # ------------------------------------------------------------------------------------------------
  # One key per environment and per service: dev-s3, int-s3, prod-s3, dev-rds, ..., prod-ddb.
  # ------------------------------------------------------------------------------------------------
  key_matrix = {
    for pair in setproduct(keys(var.workload_accounts), var.services) :
    "${pair[0]}-${pair[1]}" => {
      environment = pair[0]
      service     = pair[1]
      account_id  = var.workload_accounts[pair[0]]

      current_generation   = try(var.key_rotation_state["${pair[0]}-${pair[1]}"].current_generation, 1)
      retained_generations = try(var.key_rotation_state["${pair[0]}-${pair[1]}"].retained_generations, [])
    }
  }

  # Expand the matrix to one entry per live key generation. A rotation adds a generation here and
  # moves the previous one into retained_generations; nothing is destroyed.
  key_generations = merge([
    for key_name, cfg in local.key_matrix : {
      for generation in distinct(concat([cfg.current_generation], cfg.retained_generations)) :
      "${key_name}-gen${generation}" => merge(cfg, {
        key_name   = key_name
        generation = generation
        is_current = generation == cfg.current_generation
      })
    }
  ]...)
}

module "kms_key" {
  source   = "../../modules/kms-external-key"
  for_each = local.key_generations

  environment           = each.value.environment
  service               = each.value.service
  generation            = each.value.generation
  is_current_generation = each.value.is_current

  # Retained generations stay usable for decrypting existing ciphertext; only the ceremony flips a
  # brand-new key from PendingImport to Enabled.
  enabled                 = false
  deletion_window_in_days = var.deletion_window_in_days
  key_material_valid_to   = try(var.key_material_valid_to[each.value.key_name], null)

  consumer_account_ids = [each.value.account_id]
  consumer_principal_arns = contains(var.restrict_prod_to_principals, each.value.environment) ? lookup(
    var.environment_principal_arns, each.value.environment, []
  ) : []

  key_admin_role_arns             = var.key_admin_role_arns
  key_material_importer_role_arns = var.key_material_importer_role_arns
  break_glass_role_arns           = var.break_glass_role_arns
  auditor_role_arns               = var.auditor_role_arns

  compliance_reader_arns = [
    "arn:${local.partition}:iam::${each.value.account_id}:role/${var.rotation_compliance_role_name}",
  ]

  tags = {
    Environment = each.value.environment
    Service     = each.value.service
  }
}
