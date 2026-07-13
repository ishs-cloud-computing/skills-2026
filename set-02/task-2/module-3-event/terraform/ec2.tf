# ---------------------------------------------------------------------------
# EC2 + SG (과제지 2. EC2, 3. Security Group)
# - SG 는 최소 구성(과제지) = 인바운드 0개. mark 3-4 가 "SG Inbound Count = 0" 을
#   채점하므로 기준선이 0이어야 sg-remediation 결과가 결정적이다.
# - 접속은 SSM Session Manager (인바운드 불필요, egress 443 으로 충분)
# - 인스턴스 프로파일 이름 = 역할 이름: role-remediation 람다가
#   ROLE_NAME(wsc2026-event-ec2-role)을 프로파일 Name 으로 원복에 사용한다.
# ---------------------------------------------------------------------------

resource "aws_security_group" "event" {
  name        = var.sg_name
  description = "wsc2026 event target - no inbound baseline"
  vpc_id      = aws_vpc.event.id

  egress {
    description = "HTTP outbound (anyopen - task rule 6)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS outbound (anyopen - task rule 6, SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.sg_name }
}

resource "aws_iam_role" "ec2" {
  name               = var.ec2_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_role_name
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "event" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this[var.instance_subnet_name].id
  vpc_security_group_ids = [aws_security_group.event.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.instance_name }

  lifecycle {
    # type-remediation 데모 후 t3.micro 로 원복돼도 terraform 이 재생성하지 않게
    ignore_changes = [instance_type]
  }
}
