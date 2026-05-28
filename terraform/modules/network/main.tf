# Minimal VPC module - illustrative, not production-complete.
# Real modules in this layout also create subnets, route tables, IGW/NAT, etc.

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}"
  }
}
