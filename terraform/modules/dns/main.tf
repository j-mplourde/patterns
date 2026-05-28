# DNS record module. Designed to be called with an ALIASED provider so the
# record lands in the shared *networking* account's hosted zone:
#
#   module "dns" {
#     source    = "../../../../../modules/dns"
#     providers = { aws = aws.networking_account }
#     ...
#   }

variable "hosted_zone_id" { type = string }
variable "record_name" { type = string }
variable "record_type" {
  type    = string
  default = "A"
}
variable "record_values" { type = list(string) }
variable "ttl" {
  type    = number
  default = 300
}

resource "aws_route53_record" "this" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = var.record_type
  ttl     = var.ttl
  records = var.record_values
}

output "fqdn" {
  value = aws_route53_record.this.fqdn
}
