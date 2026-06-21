output "detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "detector_arn" {
  description = "GuardDuty detector ARN"
  value       = aws_guardduty_detector.main.arn
}

output "findings_event_rule_arn" {
  description = "EventBridge rule ARN for routing high-severity GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_high_severity.arn
}

output "alerts_topic_arn" {
  description = "SNS topic ARN for GuardDuty alerts (empty when alarm_email is not set)"
  value       = length(aws_sns_topic.guardduty_alerts) > 0 ? aws_sns_topic.guardduty_alerts[0].arn : ""
}
