# database/backup: AWS Backup plan + selection. Copies RDS snapshots to a vault
# in the shared *backup* account so a compromised workload account cannot delete
# its own backups. The destination vault ARN is produced by the backup-account
# stack and pulled in via a Terragrunt dependency in the workload's terragrunt.hcl.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.backup_account]
    }
  }
}

variable "project" { type = string }
variable "environment" { type = string }
variable "rds_arn" { type = string }
variable "destination_vault_arn" { type = string }

resource "aws_backup_vault" "local" {
  name = "${var.project}-${var.environment}-vault"
}

resource "aws_iam_role" "backup" {
  name = "${var.project}-${var.environment}-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "this" {
  name = "${var.project}-${var.environment}"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.local.name
    schedule          = "cron(0 5 ? * * *)"

    # Cross-account copy into the central backup vault.
    copy_action {
      destination_vault_arn = var.destination_vault_arn
      lifecycle { delete_after = 35 }
    }

    lifecycle { delete_after = 7 }
  }
}

resource "aws_backup_selection" "this" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.project}-${var.environment}-selection"
  plan_id      = aws_backup_plan.this.id
  resources    = [var.rds_arn]
}
