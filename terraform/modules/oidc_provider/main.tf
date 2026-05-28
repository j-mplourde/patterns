# oidc_provider: IAM OIDC trust + role for a CI system (GitHub Actions,
# Bitbucket Pipelines, etc.). Lives in the operations-tooling account so a
# single OIDC provider serves every workload account via assume-role.
#
# Workload accounts each create their own role that trusts THIS provider
# (cross-account assume) and scopes the trust to the CI claim (repo + branch).

variable "provider_url" {
  type        = string
  description = "OIDC issuer URL, e.g. https://token.actions.githubusercontent.com or https://api.bitbucket.org/2.0/workspaces/<ws>/pipelines-config/identity/oidc"
}
variable "client_ids" { type = list(string) }
variable "thumbprints" { type = list(string) }
variable "role_name" { type = string }
variable "allowed_subjects" {
  type        = list(string)
  description = "Subject claims allowed to assume (e.g. repo:org/repo:ref:refs/heads/main)"
}
variable "role_policies" {
  type    = list(string)
  default = []
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = var.provider_url
  client_id_list  = var.client_ids
  thumbprint_list = var.thumbprints
}

resource "aws_iam_role" "ci" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.this.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "${replace(var.provider_url, "https://", "")}:sub" = var.allowed_subjects
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ci" {
  for_each   = toset(var.role_policies)
  role       = aws_iam_role.ci.name
  policy_arn = each.value
}

output "provider_arn" { value = aws_iam_openid_connect_provider.this.arn }
output "ci_role_arn" { value = aws_iam_role.ci.arn }
