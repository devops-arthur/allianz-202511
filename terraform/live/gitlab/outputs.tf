output "gitlab_url" {
  value = "https://${module.gitlab.alb_dns_name}"
}

output "rds_endpoint" {
  value = module.gitlab.rds_endpoint
}

output "efs_id" {
  value = module.gitlab.efs_id
}
