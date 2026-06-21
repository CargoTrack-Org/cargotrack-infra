output "db_endpoint" {
  value = aws_db_instance.database.endpoint
}

output "db_identifier" {
  value = aws_db_instance.database.identifier
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.database.arn
}

output "application_secret_arn" {
  value = aws_secretsmanager_secret.application.arn
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}
