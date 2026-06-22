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

# ---------------------------------------------------------------------------
# EKS Control Plane 추가 Security Group
# - eksctl cluster.yaml 의 vpc.securityGroup 으로 지정한다.
# - EKS 매니지드 cluster SG 는 클러스터 생성 시점에야 만들어져 terraform 으로
#   미리 규칙을 넣을 수 없다. 대신 이 SG 를 control plane ENI 에 함께 attach 하면
#   eksctl create cluster 직후 bastion 이 곧바로 private API(443) 에 접근 가능하다.
#   (생성 후 수동으로 SG 규칙 추가하던 단계를 제거)
# ---------------------------------------------------------------------------
resource "aws_security_group" "eks_control_plane_extra" {
  name        = "wsc-eks-control-plane-extra-sg"
  description = "Extra control plane SG - allow bastion to reach private API (443)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS to EKS API from bastion"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-eks-control-plane-extra-sg" }
}
