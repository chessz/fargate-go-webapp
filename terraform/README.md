# Terraform ECS Fargate

A set of Terraform templates used for provisioning web application stacks on [AWS ECS Fargate][fargate].

## Components

### base

These components are shared by all environments.

| Name | Description | Optional |
|------|-------------|:---:|
| [main.tf] | AWS provider, output |  |
| [outputs.tf] | Terminal output display  |  |
| [variables.tf] | Variables for main.tf  |  |
| [aws_ecr_repository.tf] | ECR repository for application (all environments share)  |  ||
