variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the customer managed KMS key for DynamoDB SSE"
  type        = string
}
