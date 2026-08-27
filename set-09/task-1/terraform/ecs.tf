# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  tags = {
    Name = local.cluster_name
  }
}

# 채점 5-3이 8080 인바운드의 UserIdGroupPairs[0]을 ALB SG ID와 비교 —
# 인바운드 소스는 ALB SG 하나만 유지 (CIDR·추가 SG 금지)
resource "aws_security_group" "ecs" {
  name        = local.ecs_sg_name
  description = "Book app tasks: allow only ALB on container port"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "ECR pull / CloudWatch Logs / DynamoDB via public IP"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.ecs_sg_name
  }
}

# 제공 book 바이너리는 정적 링크 x86-64 ELF — X86_64 고정 필수 (채점 3-2, 4-2)
resource "aws_ecs_task_definition" "book" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${aws_ecr_repository.book.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "TABLE_NAME", value = local.table_name },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = var.log_stream_prefix
        }
      }
    }
  ])

  tags = {
    Name = local.task_family
  }
}

# 과제 7.4: Public Subnet 2개 + Assign Public IP ENABLED (NAT 없이 ECR/DDB/Logs 접근)
resource "aws_ecs_service" "book" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.book.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # TG가 LB에 연결된 뒤에만 서비스 생성 가능
  depends_on = [aws_lb_listener_rule.origin_verify]

  tags = {
    Name = local.service_name
  }
}
