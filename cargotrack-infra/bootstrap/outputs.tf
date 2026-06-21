output "state_bucket_name" {
  description = "S3 bucket name to use in the backend configuration"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state S3 bucket"
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name to use in the backend configuration"
  value       = aws_dynamodb_table.locks.name
}
