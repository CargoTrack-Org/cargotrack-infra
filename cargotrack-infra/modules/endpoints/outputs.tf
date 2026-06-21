output "s3_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  description = "Map of interface endpoint IDs keyed by service name"
  value       = { for k, ep in aws_vpc_endpoint.interface : k => ep.id }
}

output "endpoints_security_group_id" {
  description = "Security group ID attached to all interface endpoints"
  value       = aws_security_group.endpoints.id
}
