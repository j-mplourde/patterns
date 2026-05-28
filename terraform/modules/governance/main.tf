# governance: account-level security posture. GuardDuty for threat detection,
# Security Hub for findings aggregation, Inspector2 for vulnerability scanning.
# Applied uniformly across every workload account.

resource "aws_guardduty_detector" "this" {
  enable = true
  datasources {
    s3_logs { enable = true }
    kubernetes { audit_logs { enable = false } }
    malware_protection {
      scan_ec2_instance_with_findings { ebs_volumes { enable = true } }
    }
  }
}

resource "aws_securityhub_account" "this" {
  enable_default_standards = true
}

resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.this.account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]
}

data "aws_caller_identity" "this" {}

output "guardduty_detector_id" { value = aws_guardduty_detector.this.id }
