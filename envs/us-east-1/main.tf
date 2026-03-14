terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# Pull Cognito outputs from auth state
data "terraform_remote_state" "auth" {
  backend = "local"
  config  = { path = "../../auth/terraform.tfstate" }
}

module "compute" {
  source                      = "../../modules/compute"
  region                      = "us-east-1"
  cognito_user_pool_id        = data.terraform_remote_state.auth.outputs.user_pool_id
  cognito_user_pool_client_id = data.terraform_remote_state.auth.outputs.user_pool_client_id
  your_email                  = "singh.anuragsaurabh@gmail.com"       
  github_repo                 = "https://github.com/Anurag-ini6/aws-assessment"  
}

output "api_url_us" { value = module.compute.api_url }
