# certificate: ACM certificate with DNS validation. The validation CNAME is
# created in the shared networking account, so this module takes an aliased
# provider for that account.
#
#   module "certificate" {
#     source = "../../../../../modules/certificate"
#     providers = {
#       aws                    = aws                       # workload account
#       aws.networking_account = aws.networking_account    # for the validation record
#     }
#     ...
#   }

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.networking_account]
    }
  }
}

variable "domain_name" { type = string }
variable "subject_alternative_names" {
  type    = list(string)
  default = []
}
variable "hosted_zone_id" { type = string }

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validation" {
  provider = aws.networking_account
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.this.certificate_arn
}
