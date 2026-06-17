# ---------------------------------------------------------------------------
# Bastion (요구사항 5)
# - Public Subnet 배치, EIP 로 재시작 시에도 IP 고정
# - SSH(22) 만 허용
# - SSH Password 방식(Skill53##), Admin 권한(AdministratorAccess) IAM Role
# - 패키지: awscliv2, jq, curl, ping, kubectl, eksctl
# - Tag: Name=wsc-bastion
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "wsc-bastion-sg"
  description = "Bastion - allow SSH inbound only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 유의사항 6: 80/443 Outbound Anyopen + 전체 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-bastion-sg" }
}

# ----- Admin 권한 IAM Role -----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "wsc-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "wsc-bastion-profile"
  role = aws_iam_role.bastion.name
}

# ----- EIP -----
resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = { Name = "wsc-bastion-eip" }
}

# ----- User Data: 패키지 설치 + SSH Password 설정 -----
locals {
  bastion_user_data = templatefile("${path.module}/bastion_user_data.sh.tpl", {
    ssh_password = var.ssh_password
    cluster_name = var.cluster_name
    region       = var.region
  })
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.this[local.public_subnet_keys[0]].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = local.bastion_user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 강제
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wsc-bastion" }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
