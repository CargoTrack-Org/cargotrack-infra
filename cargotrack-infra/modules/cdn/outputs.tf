output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL attached to CloudFront"
  value       = aws_wafv2_web_acl.main.arn
}
