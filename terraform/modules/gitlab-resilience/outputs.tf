output "alb_dns_name" {
  description = "DNS name of the GitLab ALB."
  value       = aws_lb.gitlab.dns_name
}

output "efs_id" {
  description = "EFS file system ID."
  value       = aws_efs_file_system.gitlab.id
}

output "rds_endpoint" {
  description = "RDS instance endpoint."
  value       = aws_db_instance.gitlab.address
}

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = aws_autoscaling_group.gitlab.name
}
