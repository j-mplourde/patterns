# encryption: KMS customer-managed key + alias for use by RDS, S3, Secrets
# Manager, etc. Per-environment keys (not shared across accounts) keep blast
# radius tight on key compromise.

variable "alias" { type = string }
variable "description" {
  type    = string
  default = "Workload-scoped CMK"
}
variable "deletion_window_in_days" {
  type    = number
  default = 30
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

output "kms_key_arn" { value = aws_kms_key.this.arn }
output "kms_key_id" { value = aws_kms_key.this.key_id }
