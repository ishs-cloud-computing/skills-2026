# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "app" {
  name        = "${var.ec2_name}-sg"
  description = "bigbae nosql app"
  vpc_id      = aws_vpc.this.id

  # 채점이 인터넷에서 curl 하므로 8080 전체 개방 필수.
  ingress {
    description = "app port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 유의사항 6: outbound 80/443 any open.
  egress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# app.py 가 쓰는 API 전부: update_item(reserve/cancel), query(테이블 + GSI).
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.reservation.arn]
  }

  statement {
    actions = ["dynamodb:Query"]
    resources = [
      aws_dynamodb_table.reservation.arn,
      "${aws_dynamodb_table.reservation.arn}/index/${var.gsi_name}",
    ]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.ec2_name}-policy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.ec2_name}-profile"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    app_b64    = base64encode(file("${path.module}/../../provided/module-1/app.py"))
    req_b64    = base64encode(file("${path.module}/../../provided/module-1/requirements.txt"))
    region     = var.region
    table_name = var.reservation_table_name
    gsi_name   = var.gsi_name
  })

  tags = {
    Name = var.ec2_name
  }
}
