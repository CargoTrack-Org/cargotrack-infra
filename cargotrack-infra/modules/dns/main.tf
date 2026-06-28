locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  enabled = var.domain_name != ""
}

resource "aws_route53_zone" "main" {
  count = local.enabled ? 1 : 0

  name = var.domain_name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-hosted-zone"
    }
  )
}

resource "aws_acm_certificate" "main" {
  count = local.enabled ? 1 : 0

  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-certificate"
    }
  )
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.enabled ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count = local.enabled ? 1 : 0

  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
