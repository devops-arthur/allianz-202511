output "current_key_arns" {
  description = "Key name (<env>-<service>) -> ARN of the current generation. Feed these into the workload accounts."
  value = {
    for key_name, cfg in local.key_matrix :
    key_name => module.kms_key["${key_name}-gen${cfg.current_generation}"].key_arn
  }
}

output "service_alias_arns" {
  description = "Key name -> cross-account alias ARN the workloads reference (alias/<env>-<service>)."
  value = {
    for key_name, cfg in local.key_matrix :
    key_name => module.kms_key["${key_name}-gen${cfg.current_generation}"].service_alias_arn
  }
}

output "keys_by_environment" {
  description = "Per environment, the alias ARN of every service key. Convenient input for the workload roots."
  value = {
    for environment in keys(var.workload_accounts) :
    environment => {
      for service in var.services :
      service => module.kms_key["${environment}-${service}-gen${local.key_matrix["${environment}-${service}"].current_generation}"].service_alias_arn
    }
  }
}

output "all_key_generations" {
  description = "Every live key generation with its state - the rotation inventory."
  value = {
    for generation_key, mod in module.kms_key :
    generation_key => {
      key_arn        = mod.key_arn
      key_state      = mod.key_state
      generation     = mod.generation
      is_current     = mod.is_current_generation
      alias          = mod.generation_alias_name
      service_alias  = mod.service_alias_name
    }
  }
}

output "pending_import_keys" {
  description = "Keys still waiting for the HSM key material ceremony. Must be empty before a rotation is considered done."
  value = [
    for generation_key, mod in module.kms_key : generation_key if mod.key_state == "PendingImport"
  ]
}
