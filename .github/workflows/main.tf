###############################################################
# AWS ALB Path-Based Routing — Terraform
# Project 1: Homepage / Images / Register routing via ALB
###############################################################

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################
# DATA — Latest Amazon Linux 2023 AMI
###############################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################
# VPC
###############################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

###############################################################
# PUBLIC SUBNETS — one per AZ
###############################################################

resource "aws_subnet" "public" {
  for_each = {
    az1 = { cidr = "10.0.1.0/24", az = "${var.aws_region}a" }
    az2 = { cidr = "10.0.2.0/24", az = "${var.aws_region}b" }
    az3 = { cidr = "10.0.3.0/24", az = "${var.aws_region}c" }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-subnet-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

###############################################################
# SECURITY GROUPS
###############################################################

# ALB — accepts HTTP from anywhere
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-alb" }
}

# EC2 — accepts HTTP only from ALB SG
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Optional: allow SSH from your IP (set var.ssh_cidr)
  dynamic "ingress" {
    for_each = var.ssh_cidr != "" ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-ec2" }
}

###############################################################
# EC2 INSTANCES (A / B / C) — one per AZ
###############################################################

locals {
  instances = {
    a = {
      subnet_key = "az1"
      user_data  = base64encode(file("${path.module}/user_data_a.sh"))
      name       = "${var.project_name}-instance-a-homepage"
    }
    b = {
      subnet_key = "az2"
      user_data  = base64encode(file("${path.module}/user_data_b.sh"))
      name       = "${var.project_name}-instance-b-images"
    }
    c = {
      subnet_key = "az3"
      user_data  = base64encode(file("${path.module}/user_data_c.sh"))
      name       = "${var.project_name}-instance-c-register"
    }
  }
}

resource "aws_instance" "app" {
  for_each = local.instances

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[each.value.subnet_key].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  user_data_base64       = each.value.user_data

  tags = { Name = each.value.name }
}

###############################################################
# TARGET GROUPS
###############################################################

resource "aws_lb_target_group" "tg_a" {
  name        = "${var.project_name}-tg-a"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.project_name}-tg-a" }
}

resource "aws_lb_target_group" "tg_b" {
  name        = "${var.project_name}-tg-b"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/images"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.project_name}-tg-b" }
}

resource "aws_lb_target_group" "tg_c" {
  name        = "${var.project_name}-tg-c"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/register"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.project_name}-tg-c" }
}

###############################################################
# TARGET GROUP ATTACHMENTS
###############################################################

resource "aws_lb_target_group_attachment" "tg_a" {
  target_group_arn = aws_lb_target_group.tg_a.arn
  target_id        = aws_instance.app["a"].id
  port             = 80
}

resource "aws_lb_target_group_attachment" "tg_b" {
  target_group_arn = aws_lb_target_group.tg_b.arn
  target_id        = aws_instance.app["b"].id
  port             = 80
}

resource "aws_lb_target_group_attachment" "tg_c" {
  target_group_arn = aws_lb_target_group.tg_c.arn
  target_id        = aws_instance.app["c"].id
  port             = 80
}

###############################################################
# APPLICATION LOAD BALANCER
###############################################################

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  enable_deletion_protection = false

  tags = { Name = "${var.project_name}-alb" }
}

###############################################################
# LISTENER + ROUTING RULES
###############################################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action → Target Group A (homepage)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_a.arn
  }
}

# Priority 1 — /images → Target Group B
resource "aws_lb_listener_rule" "images" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/images", "/images/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_b.arn
  }
}

# Priority 2 — /register → Target Group C
resource "aws_lb_listener_rule" "register" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  condition {
    path_pattern {
      values = ["/register", "/register/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_c.arn
  }
}
