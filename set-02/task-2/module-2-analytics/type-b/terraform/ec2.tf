# ---------------------------------------------------------------------------
# EC2 (과제지 2. EC2, Application.md, mark 2-1/2-5/2-6)
# - analytics-priv-a 배치 (mark 2-1 이 서브넷 Name 태그를 채점)
# - user_data 가 부팅 시 pip 설치를 하므로 NAT 라우트가 먼저 있어야 한다
#   (없으면 앱 설치가 조용히 실패 → mark 2-5/2-6 전멸)
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this[var.app_subnet_name].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    # provided 원본을 그대로 주입 (수정 금지 — Application.md)
    app_py       = file("${path.module}/../../../provided/module2/app.py")
    requirements = file("${path.module}/../../../provided/module2/requirements.txt")
    stream_name  = aws_kinesis_stream.orders.name
    region       = var.region
    app_port     = var.app_port
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.instance_name }

  depends_on = [
    aws_nat_gateway.analytics,
    aws_route.private_default,
  ]
}
