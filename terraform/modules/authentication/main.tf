# authentication: Cognito user pool for the web app (hosted/managed login,
# branding, app client). Lives in the workload account that owns the app.

variable "project" { type = string }
variable "environment" { type = string }
variable "callback_urls" { type = list(string) }

resource "aws_cognito_user_pool" "this" {
  name                     = "${var.project}-${var.environment}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name                                 = "${var.project}-web"
  user_pool_id                         = aws_cognito_user_pool.this.id
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = var.callback_urls
  supported_identity_providers         = ["COGNITO"]
}

output "user_pool_id" { value = aws_cognito_user_pool.this.id }
output "web_client_id" { value = aws_cognito_user_pool_client.web.id }
