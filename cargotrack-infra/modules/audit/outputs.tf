output "table_name" {
  description = "DynamoDB audit table name"
  value       = aws_dynamodb_table.audit.name
}

output "table_arn" {
  description = "DynamoDB audit table ARN"
  value       = aws_dynamodb_table.audit.arn
}
