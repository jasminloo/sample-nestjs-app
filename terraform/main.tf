terraform {
  backend "s3" {
    region = "ap-southeast-1"
    bucket = "terraform-app-state"
    key    = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "ecr_repo" {
  name                 = "nestjs-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "nestjs-app" 
}

resource "aws_default_vpc" "default_vpc" {
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "ap-southeast-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "ap-southeast-1b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "ap-southeast-1c"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = "${aws_iam_role.ecs_task_execution_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ssm_parameter" "ecs_parameter" {
  name        = "/your-app-config/your-parameter-name" // Set your desired parameter name
  description = "Your application configuration parameter" // Set your description
  type        = "SecureString"
  value       = "your-parameter-value" // Set your parameter value
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "nestjs-task" 
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"] 
  task_role_arn            = "${aws_iam_role.ecs_task_execution_role.arn}" 
  execution_role_arn       = "${aws_iam_role.ecs_task_execution_role.arn}"

  container_definitions = jsonencode([
    {
      name  = "nestjs-container"
      image = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
      cpu   = 256 
      memory = 512 
      portMappings = [{
        containerPort = 3001 
        hostPort      = 3001 
      }]
      environment = [
        {
          name  = "filename"
          valueFrom = "${aws_ssm_parameter.ecs_parameter.arn}"
        }
      ]
    }
  ])
}

resource "aws_lb" "application_load_balancer" {
  name               = "nestjs-lb"
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 3001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_lb.application_load_balancer.arn}"
  port              = "3001"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
  }
}

resource "aws_ecs_service" "ecs_service" {
  name            = "nestjs-ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name   = "${aws_ecs_task_definition.ecs_task_definition.family}"
    container_port   = 3001 
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true
  }
}
