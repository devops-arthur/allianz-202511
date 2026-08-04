output "recorder_name" {
  description = "Name of the configuration recorder."
  value       = aws_config_configuration_recorder.this.name
}

output "role_arn" {
  description = "ARN of the AWS Config service role."
  value       = aws_iam_role.config.arn
}

output "recorder_status_id" {
  description = "Recorder status resource id - depend on this to make sure rules are created after recording starts."
  value       = aws_config_configuration_recorder_status.this.id
}
