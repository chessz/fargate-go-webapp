#!/bin/bash

show_creds() 
{

  # Confirm and export AWS credentials
  echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
  echo "AWS_SECRET_ACCESS_KEY:" $(echo $AWS_SECRET_ACCESS_KEY | sed 's/.*\(....\)/************\1/')
  echo "AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"

}

aws_creds()
{

  export AWS_ACCESS_KEY_ID=$(grep 'aws_access_key_id' ~/.aws/credentials | awk '{print $3}')
  export AWS_SECRET_ACCESS_KEY=$(grep 'aws_secret_access_key' ~/.aws/credentials | awk '{print $3}')
  export AWS_DEFAULT_REGION=$(grep 'region' ~/.aws/config | awk '{print $3}')

  # Display AWS Credentials
  show_creds
}

creds_banner()
{
  # AWS Credentials Banner
  echo -e
  echo "---------------"
  echo "AWS Credentials"
  echo "---------------"
}

tf_banner()
{
  # Terraform Banner
  echo -e
  echo "----------"
  echo "Terraform "
  echo "----------"
}

manual_creds()
{

echo -e "\nSpecify AWS credentials here..."

# Get AWS Secret and Key from the user
read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo  # Move to the next line after entering the secret key

# Prompt for AWS Region
read -p "Enter AWS Default Region: " AWS_DEFAULT_REGION

# Export these environment variables
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

# Display credentials
creds_banner
show_creds

# Prompt for confirmation
read -p "Are these credentials correct? (y/n): " confirm
if [[ $confirm != "y" ]]; then
  echo "Exiting..."
  exit 1
fi

deployment

}

deployment()
{

clear
creds_banner
show_creds

# Run Terraform for ECR creation
cd ../terraform
tf_banner
cat <<EOF > terraform.tfvars
aws_access_key = "${AWS_ACCESS_KEY_ID}"
aws_secret_key = "${AWS_SECRET_ACCESS_KEY}"
aws_region = "${AWS_DEFAULT_REGION}"
EOF
terraform init
terraform apply -target=aws_ecr_repository.pw_ecr_dsop_webapp -auto-approve

# Run Terraform to get the output
ecr_rep_uri=$(echo `terraform output ecr_repository_uri | tr -d '"'`)

# You can now use $output_value in your Bash script
echo "The value of ecr_repository_uri is: ${ecr_rep_uri}"

# Push Docker image to AWS ECR
# <ecr_repository_url> lookup is from the terraform output
cd ..
echo -e "Current Directory: $PWD"
aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${ecr_rep_uri}
docker build -t pw_ecr_dsop_webapp .
docker tag pw_ecr_dsop_webapp:latest ${ecr_rep_uri}:latest
docker push ${ecr_rep_uri}:latest

# Run another Terraform command
cd terraform
tf_banner
terraform apply -auto-approve

# Task 5: Display the URL of the ALB
# Replace <your_alb_dns_name> with the actual ALB DNS name
alb_hostname_url=$(echo `terraform output alb_hostname | tr -d '"'`)
echo "ALB URL: http://${alb_hostname_url}:8080"

}

# Confirm and export AWS credentials
creds_banner 

# Confirm and export AWS credentials
# Get AWS Secret and Key from ~/.aws/credentials and confirm with user
if [[ -f ~/.aws/credentials ]]; then
  aws_creds
else
  echo "AWS credentials not found in ~/.aws/credentials. Please configure your AWS credentials first."
  exit 1
fi

read -p "Are these credentials correct? (y/n): " confirm
if [[ $confirm == "n" ]]; then
  manual_creds
elif [[ $confirm == "y" ]]; then
  deployment
else
  echo "Exiting..."
  exit 1
fi
