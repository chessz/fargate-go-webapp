# Specify AWS region
provider "aws" {
  region = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Create an ECR for a docker container
resource "aws_ecr_repository" "pw_ecr_dsop_webapp" {
  name = "pw_ecr_dsop_webapp"  
  image_tag_mutability = "MUTABLE"
  force_delete = true
}

# Show the ECR URI end-point
output "ecr_repository_uri" {
  value = aws_ecr_repository.pw_ecr_dsop_webapp.repository_url
}