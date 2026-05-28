# identity_center: AWS Identity Center (SSO) permission sets, groups, and
# account assignments. Runs in the MANAGEMENT account only. Each permission set
# maps a job role (Admin / Developer / ReadOnly) to the set of workload accounts
# it can access.

variable "permission_set_name" { type = string }
variable "managed_policies" {
  type    = list(string)
  default = []
}
variable "session_duration" {
  type    = string
  default = "PT8H"
}
variable "group_id" { type = string }
variable "account_ids" { type = list(string) }

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

resource "aws_ssoadmin_permission_set" "this" {
  name             = var.permission_set_name
  instance_arn     = local.sso_instance_arn
  session_duration = var.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each           = toset(var.managed_policies)
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value
  permission_set_arn = aws_ssoadmin_permission_set.this.arn
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each           = toset(var.account_ids)
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this.arn
  principal_id       = var.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

output "permission_set_arn" { value = aws_ssoadmin_permission_set.this.arn }
