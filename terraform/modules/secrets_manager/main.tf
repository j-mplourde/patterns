# secrets_manager: SSM Parameter Store entries for non-secret application
# configuration (and SecureString for secret config). For high-value secrets
# (DB passwords, API tokens) the database module uses RDS-managed passwords
# in real Secrets Manager - this module covers the long tail of config.

variable "prefix" { type = string }
variable "parameters" {
  type = map(object({
    value  = string
    secure = bool
  }))
  description = "Map of parameter short name -> value + secure flag. Stored at /<prefix>/<short name>."
}

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name  = "/${var.prefix}/${each.key}"
  type  = each.value.secure ? "SecureString" : "String"
  value = each.value.value
}

output "parameter_arns" {
  value = { for k, p in aws_ssm_parameter.this : k => p.arn }
}
