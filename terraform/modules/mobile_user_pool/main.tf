# mobile_user_pool: Cognito user pool sized for mobile clients. Separate from
# the web `authentication` pool so token scopes, MFA, and password policies can
# diverge without coupling the two surfaces.

variable "project" { type = string }
variable "environment" { type = string }

resource "aws_cognito_user_pool" "this" {
  name                     = "${var.project}-${var.environment}-mobile"
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"
  software_token_mfa_configuration { enabled = true }

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "mobile" {
  name                  = "${var.project}-mobile"
  user_pool_id          = aws_cognito_user_pool.this.id
  generate_secret       = false
  explicit_auth_flows   = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  refresh_token_validity = 30
}

output "user_pool_id" { value = aws_cognito_user_pool.this.id }
output "mobile_client_id" { value = aws_cognito_user_pool_client.mobile.id }
