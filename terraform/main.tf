##############
### Network
##############

# Fetch Availability Zones (AZs) in the current region
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "172.17.0.0/16"
}

# Create var.az_count private subnets, each in a different AZ
resource "aws_subnet" "private" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.main.id}"
}

# Create var.az_count public subnets, each in a different AZ
resource "aws_subnet" "public" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${aws_vpc.main.id}"
  map_public_ip_on_launch = true
}

# Internet Gateway (IGW) for the public subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"
}

# Route the public subnet traffic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

# Create a NAT gateway with an EIP for each private subnet to get internet connectivity
resource "aws_eip" "gw" {
  count      = "${var.az_count}"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "gw" {
  count         = "${var.az_count}"
  subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"
  allocation_id = "${element(aws_eip.gw.*.id, count.index)}"
}

# Create a new route table for the private subnets
# And make it route non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "private" {
  count  = "${var.az_count}"
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.gw.*.id, count.index)}"
  }
}

# Explicitely associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

################
### Security
################

# ALB Security group
# This is the group you need to edit if you want to restrict access to your application
resource "aws_security_group" "lb" {
  name        = "pwdevops-ecs-alb"
  description = "controls access to the ALB"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "pwdevops-ecs-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.app_port}"
    to_port         = "${var.app_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##########
### ALB
##########

resource "aws_alb" "main" {
  name            = "pwdevops-go-webapp"
  subnets         = "${aws_subnet.public.*.id}"
  security_groups = [aws_security_group.lb.id]
}

resource "aws_alb_target_group" "app" {
  name        = "pwdevops-go-webapp"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.main.id}"
  target_type = "ip"
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.app.id}"
    type             = "forward"
  }
}

#########
### ECS
#########

resource "aws_ecs_cluster" "main" {
  name = "pwdsop-ecs-cluster"
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

resource "aws_ecs_task_definition" "app" {
  family                   = "app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${aws_ecr_repository.pw_ecr_dsop_webapp.repository_url}:latest",
    "memory": ${var.fargate_memory},
    "name": "app",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "main" {
  name            = "pwdevops-ecs-service"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = "${var.app_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = ["${aws_security_group.ecs_tasks.id}"]
    subnets         = "${aws_subnet.private.*.id}"
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "app"
    container_port   = "${var.app_port}"
  }

  depends_on = [aws_alb_listener.front_end,]
}

##############
### CloudWatch
##############

# Create an SNS topic
resource "aws_sns_topic" "dsop_sns" {
  name = "GoWebAppSNS" # Replace with your desired topic name
}

# Retrieve the ARN of an existing SNS topic
data "aws_sns_topic" "this" {
  name = aws_sns_topic.dsop_sns.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.dsop_sns.arn
}

# Create the log group
resource "aws_cloudwatch_log_group" "dsop-lgrp" {
  name = "chessz-go-webapp-log" 
}

# CloudWatch Log Metric Filter
resource "aws_cloudwatch_log_metric_filter" "http_500_filter" {
  name           = "http_500_filter"
  pattern        = "[timestamp, errorCode, message]"
  log_group_name = aws_cloudwatch_log_group.dsop-lgrp.name
  metric_transformation {
    name      = "Http500Errors"
    namespace = "CustomMetrics"
    value     = "1"
  }
}

# To email
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.dsop_sns.arn # Use the ARN of your SNS topic
  protocol  = "email"
  endpoint  = "mzul@pm.me" 
}

# CloudWatch Alarm for HTTP 500 Errors
resource "aws_cloudwatch_metric_alarm" "http_500_alarm" {
  alarm_name          = "Http500ErrorsAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = 1
  metric_name         = "Http500Errors"
  namespace           = "CustomMetrics"
  period              = 60
  statistic           = "SampleCount"
  threshold           = 1
  alarm_description   = "HTTP 500 Errors Alarm"
  alarm_actions = [data.aws_sns_topic.this.arn]
  dimensions = {
    LogGroupName = "chessz-go-webapp-log" 
  }
}