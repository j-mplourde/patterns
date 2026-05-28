# email: SES sending identity. Verifies a domain, enables DKIM, and exposes a
# configuration set for bounce/complaint event publishing.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.networking_account]
    }
  }
}

variable "domain_name" { type = string }
variable "hosted_zone_id" { type = string }

resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# DKIM CNAMEs live in the networking account's hosted zone.
resource "aws_route53_record" "dkim" {
  provider = aws.networking_account
  count    = 3
  zone_id  = var.hosted_zone_id
  name     = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type     = "CNAME"
  ttl      = 300
  records  = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_sesv2_configuration_set" "this" {
  configuration_set_name = replace(var.domain_name, ".", "-")
  reputation_options { reputation_metrics_enabled = true }
}

output "domain_identity_arn" { value = aws_ses_domain_identity.this.arn }
output "configuration_set_name" { value = aws_sesv2_configuration_set.this.configuration_set_name }
