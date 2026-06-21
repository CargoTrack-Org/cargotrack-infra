# ── GuardDuty Detector ────────────────────────────────────────────────────────
# Enables GuardDuty in the region — the primary threat detection service.
# GuardDuty analyzes CloudTrail logs, VPC Flow Logs, DNS query logs, and
# Kubernetes audit logs to detect threats like privilege escalation, credential
# compromise, crypto mining, and data exfiltration.
#
# EKS Protection: Requires the separate EKS audit log source (below).
# Runtime Monitoring: Detects container-level threats in EKS pods.
# Cost: ~$0.10-0.50/month for this scale — negligible.

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name      = "${var.project_name}-guardduty"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# ── GuardDuty Findings → EventBridge → SNS ────────────────────────────────────
# Routes HIGH/CRITICAL severity GuardDuty findings to an SNS topic.
# If alarm_email is set, an SNS subscription is created so findings trigger emails.
# Severity 7+ = HIGH, Severity 9+ = CRITICAL.

resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "${var.project_name}-guardduty-high-severity"
  description = "Route GuardDuty HIGH/CRITICAL findings (severity >= 7) to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = {
    Name      = "${var.project_name}-guardduty-high-severity-rule"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count     = var.alarm_email != null && var.alarm_email != "" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "GuardDutySNS"
  arn       = aws_sns_topic.guardduty_alerts[0].arn
}

resource "aws_sns_topic" "guardduty_alerts" {
  count             = var.alarm_email != null && var.alarm_email != "" ? 1 : 0
  name              = "${var.project_name}-guardduty-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name      = "${var.project_name}-guardduty-alerts"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "guardduty_email" {
  count     = var.alarm_email != null && var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_sns_topic_policy" "guardduty_alerts" {
  count  = var.alarm_email != null && var.alarm_email != "" ? 1 : 0
  arn    = aws_sns_topic.guardduty_alerts[0].arn
  policy = data.aws_iam_policy_document.guardduty_sns.json
}

data "aws_iam_policy_document" "guardduty_sns" {
  statement {
    actions   = ["SNS:Publish"]
    resources = var.alarm_email != null && var.alarm_email != "" ? [aws_sns_topic.guardduty_alerts[0].arn] : ["*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}
