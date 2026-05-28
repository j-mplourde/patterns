# database: RDS PostgreSQL instance for the workload. Pairs with the nested
# `backup/` sub-module that ships snapshots to the central backup account.

variable "project" { type = string }
variable "environment" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_security_group_ids" { type = list(string) }
variable "kms_key_arn" { type = string }
variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "this" {
  identifier             = "${var.project}-${var.environment}"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.instance_class
  allocated_storage      = 20
  storage_encrypted      = true
  kms_key_id             = var.kms_key_arn
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"
  username               = "app"
  manage_master_user_password = true
}

output "db_instance_arn" { value = aws_db_instance.this.arn }
output "db_endpoint" { value = aws_db_instance.this.endpoint }
