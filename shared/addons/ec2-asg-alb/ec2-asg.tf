# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# EC2 Auto Scaling 부착 스니펫 — Launch Template + ASG + target tracking(CPU).
# 기존 ALB 대상 그룹에 ASG 인스턴스를 등록한다 (target_group_arns).
# 원본: set-02 task-2 module-2-analytics terraform/ec2.tf·userdata.sh.tpl·alb.tf
# ---------------------------------------------------------------------------

# AL2023 최신 AMI (보안 항목이라 latest 허용 — 작업 규칙 2 예외)
data "aws_ssm_parameter" "addon_asg_al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # 기존 aws_instance 의 user_data 표현식을 base64encode(...) 로 감싸 여기에 넣는다. 예:
  # base64encode(templatefile("${path.module}/userdata.sh.tpl", { app_py = file(...), stream_name = ..., region = var.region, app_port = var.app_port }))
  addon_asg_user_data = var.addon_asg_user_data_base64
}

resource "aws_launch_template" "addon_asg" {
  name_prefix   = "${var.addon_asg_name}-"
  image_id      = data.aws_ssm_parameter.addon_asg_al2023_ami.value
  instance_type = var.addon_asg_instance_type
  user_data     = local.addon_asg_user_data != "" ? local.addon_asg_user_data : null

  vpc_security_group_ids = var.addon_asg_security_group_ids

  iam_instance_profile {
    name = var.addon_asg_instance_profile_name
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.addon_asg_root_volume_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = var.addon_asg_instance_name }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "addon" {
  name                      = var.addon_asg_name
  min_size                  = var.addon_asg_min_size
  max_size                  = var.addon_asg_max_size
  desired_capacity          = var.addon_asg_desired_capacity
  vpc_zone_identifier       = var.addon_asg_subnet_ids
  target_group_arns         = var.addon_asg_target_group_arns
  health_check_type         = length(var.addon_asg_target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = var.addon_asg_health_check_grace_period

  launch_template {
    id      = aws_launch_template.addon_asg.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.addon_asg_instance_name
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "addon_cpu" {
  name                   = "${var.addon_asg_name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.addon.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.addon_asg_cpu_target
  }
}
