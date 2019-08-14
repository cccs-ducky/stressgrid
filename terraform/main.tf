terraform {
  required_version = ">= 0.12.0"
  required_providers {
    aws = ">= 2.23.0"
    external = ">= 1.2.0"
  }
}

variable region {
  type = "string"
}

variable vpc_id {
  type = "string"
}

variable key_name {
  type = "string"
}

variable capacity {
  type    = "string"
  default = "1"
}

variable generator_instance_type {
  type    = "string"
  default = "c5.xlarge"
}

variable coordinator_instance_type {
  type    = "string"
  default = "t2.micro"
}

variable ami_owner {
  type    = "string"
  default = "198789150561"
}

provider "aws" {
  region = var.region
}

data "external" "my_ip" {
  program = ["curl", "https://api.ipify.org?format=json"]
}

data "aws_subnet_ids" "my_subnets" {
  vpc_id = var.vpc_id
}

data "aws_ami" "coordinator" {
  most_recent = true
  name_regex  = "^stressgrid-coordinator-amd64-.*"
  owners      = [var.ami_owner]
}

data "aws_ami" "generator" {
  most_recent = true
  name_regex  = "^stressgrid-generator-amd64-.*"
  owners      = [var.ami_owner]
}

resource "aws_security_group" "coordinator" {
  name   = "stressgrid-coordinator"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["${data.external.my_ip.result.ip}/32"]
  }

  ingress {
    from_port       = 9696
    to_port         = 9696
    protocol        = "tcp"
    security_groups = [aws_security_group.generator.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "generator" {
  name   = "stressgrid-generator"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "coordinator_cloudwatch" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "coordinator_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "coordinator" {
  name               = "stressgrid-coordinator"
  assume_role_policy = data.aws_iam_policy_document.coordinator_assume_role.json
}

resource "aws_iam_role_policy" "coordinator_cloudwatch" {
  name   = "stressgrid-coordinator-cloudwatch"
  role   = aws_iam_role.coordinator.id
  policy = data.aws_iam_policy_document.coordinator_cloudwatch.json
}

resource "aws_iam_instance_profile" "coordinator" {
  name = "stressgrid-coordinator"
  role = aws_iam_role.coordinator.name
}

resource "aws_instance" "coordinator" {
  ami                         = data.aws_ami.coordinator.id
  instance_type               = var.coordinator_instance_type
  key_name                    = var.key_name
  user_data                   = templatefile("${path.module}/coordinator_init.sh", { region = var.region })
  iam_instance_profile        = aws_iam_instance_profile.coordinator.id
  vpc_security_group_ids      = [aws_security_group.coordinator.id]
  associate_public_ip_address = true
  subnet_id                   = sort(data.aws_subnet_ids.my_subnets.ids)[0]

  tags = {
    Name = "stressgrid-coordinator"
  }
}

output "coordinator_url" {
  value = "http://${aws_instance.coordinator.public_dns}:8000"
}

resource "aws_launch_configuration" "generator" {
  name                        = "stressgrid-generator"
  image_id                    = data.aws_ami.generator.id
  instance_type               = var.generator_instance_type
  key_name                    = var.key_name
  user_data                   = templatefile("${path.module}/generator_init.sh", { coordinator_dns = aws_instance.coordinator.private_dns })
  security_groups             = [aws_security_group.generator.id]
  associate_public_ip_address = false
}

resource "aws_autoscaling_group" "generator" {
  name                 = "stressgrid-generator"
  launch_configuration = aws_launch_configuration.generator.name
  min_size             = 0
  max_size             = 100
  desired_capacity     = var.capacity
  vpc_zone_identifier  = data.aws_subnet_ids.my_subnets.ids

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "stressgrid-generator"
    propagate_at_launch = true
  }
}
