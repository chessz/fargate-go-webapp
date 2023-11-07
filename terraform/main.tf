# Specify AWS region
provider "aws" {
  region = "eu-west-1" 
}

# Create an ECR for a docker container
resource "aws_ecr_repository" "pw_ecr_dsop_webapp" {
  name = "pw_ecr_dsop_webapp"  
  image_tag_mutability = "MUTABLE"
}

# Create an ECS cluster
resource "aws_ecs_cluster" "pw_dsop_cluster" {
  name = "pw-dsop-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "pw_dsop_webapp_task_def" {
  family                   = "pw-dsop-webapp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  cpu    = "256"  # CPU units - 1 vCPU = 1025 CPU Units
  memory = "512"  # Memory in MiB 

  container_definitions = jsonencode([
    {
      name  = "pw-dsop-webapp"
      image = "${aws_ecr_repository.pw_ecr_dsop_webapp.repository_url}:latest"
      portMappings = [
        {
          containerPort = 8080
          hostPort = 8080
        },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = "pw-dsop-ecs-logs"
          "awslogs-region" = "eu-west-1"
          "awslogs-stream-prefix" = "pw-dsop-webapp"
        }
      }
    },
  ])
}

##################
# Network Setup
##################

resource "aws_subnet" "pw_dsop_subnet1" {
  vpc_id                  = aws_vpc.pw_dsop_vpc.id
  cidr_block              = "10.0.1.0/24"  # CIDR block
  availability_zone       = "eu-west-1a"   # Availability zone
  map_public_ip_on_launch = true           # Set to 'true' for public IPs (Optinal)
}

resource "aws_subnet" "pw_dsop_subnet2" {
  vpc_id                  = aws_vpc.pw_dsop_vpc.id
  cidr_block              = "10.0.2.0/24"  # CIDR block
  availability_zone       = "eu-west-1b"   # Availability zone
  map_public_ip_on_launch = true           # Set to 'true' for public IPs (Optinal)
}

resource "aws_vpc" "pw_dsop_vpc" {
  cidr_block = "10.0.0.0/16"  # CIDR block
}

# Define an AWS security group with the name "pw_dsop_alb_sg"
resource "aws_security_group" "pw_dsop_alb_sg" {
  name_prefix   = "pw_dsop_alb_sg"
  description   = "PW security group for the Application Load Balancer"
  vpc_id       = aws_vpc.pw_dsop_vpc.id  # Reference your VPC resource

  # Allow incoming traffic on port 8080
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this to a specific IP range if needed
  }

  egress {
   protocol         = "-1"
   from_port        = 0
   to_port          = 0
   cidr_blocks      = ["0.0.0.0/0"]
   ipv6_cidr_blocks = ["::/0"]
  }

}

# Create internet gateway
resource "aws_internet_gateway" "pw_dsop_igw" {
  vpc_id = aws_vpc.pw_dsop_vpc.id
}

# Configuring a route table
resource "aws_route_table" "pw_dsop_route_table" {
  vpc_id = aws_vpc.pw_dsop_vpc.id
}

# Route table association for subnet1
resource "aws_route_table_association" "subnet1_association" {
  subnet_id      = aws_subnet.pw_dsop_subnet1.id  
  route_table_id = aws_route_table.pw_dsop_route_table.id
}

# Route table association for subnet2
resource "aws_route_table_association" "subnet2_association" {
  subnet_id      = aws_subnet.pw_dsop_subnet2.id  
  route_table_id = aws_route_table.pw_dsop_route_table.id
}

# Create an Elastic IP for each NAT gateway
resource "aws_eip" "nat_eip_subnet1" {
  instance = null
}

# Create an Elastic IP for each NAT gateway
resource "aws_eip" "nat_eip_subnet2" {
  instance = null
}

# Create a NAT gateway in each subnet1
resource "aws_nat_gateway" "nat_gateway_subnet1" {
  allocation_id = aws_eip.nat_eip_subnet1.id
  subnet_id     = aws_subnet.pw_dsop_subnet1.id # Use the appropriate subnet
}

# Create a NAT gateway in each subnet2
resource "aws_nat_gateway" "nat_gateway_subnet2" {
  allocation_id = aws_eip.nat_eip_subnet2.id
  subnet_id     = aws_subnet.pw_dsop_subnet2.id # Use the appropriate subnet
}

# Update your route table to route traffic through the NAT gateways
resource "aws_route" "route_to_nat_gateway_subnet1" {
  route_table_id         = aws_route_table.pw_dsop_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_subnet1.id
}

##################
# ALB Setup / Expose
##################

# Create an Application Load Balancer
resource "aws_lb" "pw_dsop_alb" {
  name               = "pw-dsop-alb"
  internal           = false
  load_balancer_type = "application"
  enable_deletion_protection = false
  subnets            = [aws_subnet.pw_dsop_subnet1.id, aws_subnet.pw_dsop_subnet2.id]
  security_groups    = [aws_security_group.pw_dsop_alb_sg.id]
}

# Create a target group for the ALB
resource "aws_lb_target_group" "pw_dsop_target_group" {
  name        = "pw-dsop-target-group"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.pw_dsop_vpc.id
}

# Configure ALB listener
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.pw_dsop_alb.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = "OK"
    }
  }
}

##################
# Display / Output 
##################

# Show the ECR URI end-point
output "ecr_repository_uri" {
  value = aws_ecr_repository.pw_ecr_dsop_webapp.repository_url
}

# Show the ALB DNS Name
output "webapp_endpoint" {
  value = aws_lb.pw_dsop_alb.dns_name
}

output "nat_gateway_subnet1_eip" {
  value = aws_eip.nat_eip_subnet1.public_ip
}

output "nat_gateway_subnet2_eip" {
  value = aws_eip.nat_eip_subnet2.public_ip
}
