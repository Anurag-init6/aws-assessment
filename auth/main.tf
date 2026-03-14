provider "aws" {
  region = "us-east-1"
}

resource "aws_cognito_user_pool" "main" {
  name = "unleash-user-pool"
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "unleash-client"
  user_pool_id = aws_cognito_user_pool.main.id
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = "singh.anuragsaurabh@gmail.com"                    
  temporary_password = "Anurag123$"
  attributes = {
    email          = "singh.anuragsaurabh@gmail.com"
    email_verified = "true"
  }
  message_action = "SUPPRESS"
}

output "user_pool_id"     { value = aws_cognito_user_pool.main.id }
output "user_pool_client_id" { value = aws_cognito_user_pool_client.main.id }
