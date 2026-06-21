output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name — use this URL to access the prod frontend"
  value       = module.cdn.cloudfront_domain_name
}

output "lambda_errors_alarm_arn" {
  description = "ARN of the Lambda errors CloudWatch alarm (terraform-aws-modules/cloudwatch/aws) — alerts when document processor failures occur"
  value       = module.lambda_errors_alarm.cloudwatch_metric_alarm_arn
}
