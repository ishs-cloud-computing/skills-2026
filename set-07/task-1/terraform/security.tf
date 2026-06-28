# ---------------------------------------------------------------------------
# Security Groups
# - unicorn-vpce-sg            : VPC -> Interface Endpoint(443)
# - unicorn-alb-sg             : CloudFront origin-facing prefix list -> unicorn-alb(80) (직접 접근 차단)
# - unicorn-grafana-alb-sg     : 0.0.0.0/0 -> unicorn-grafana-alb(80) (외부 접근 허용)
# - unicorn-eks-shared-node-sg : ALB -> Pod(8080), grafana-alb -> Pod(3000) 사전 허용 (노드에 attach)
# - unicorn-eks-cp-extra-sg    : unicorn-mark(CloudShell) -> EKS private API(443)
# - unicorn-mark-sg            : 채점용 CloudShell VPC Environment SG
# 유의사항 6: 80/443 Outbound any-open (전체 egress 허용으로 충족).
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "unicorn-vpce-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "unicorn-vpce-sg" }
}

resource "aws_security_group" "alb" {
  name        = "unicorn-alb-sg"
  description = "Internal ALB - allow 80 from CloudFront only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront edge only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "unicorn-alb-sg" }
}

resource "aws_security_group" "grafana_alb" {
  name        = "unicorn-grafana-alb-sg"
  description = "Grafana ALB - allow 80 from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere (Grafana 외부 접근)"
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
  tags = { Name = "unicorn-grafana-alb-sg" }
}

# 노드에 직접 attach 하는 공용 SG. Terraform 이 만든 ALB SG 를 LB Controller 가 모르므로
# ALB -> Pod target/health check 가 노드 SG 에서 막히지 않도록 사전 허용한다.
resource "aws_security_group" "eks_shared_node" {
  name        = "unicorn-eks-shared-node-sg"
  description = "Shared node SG - allow ALB to reach Pod targets (8080/3000)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "unicorn-alb to Book App Pod (8080)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "unicorn-grafana-alb to Grafana Pod (3000)"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "unicorn-eks-shared-node-sg" }
}

# 채점용 CloudShell VPC Environment(unicorn-mark) 가 사용할 SG.
resource "aws_security_group" "mark" {
  name        = "unicorn-mark-sg"
  description = "CloudShell VPC environment (unicorn-mark) SG"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "unicorn-mark-sg" }
}

# EKS Control Plane 추가 SG: cluster.yaml 의 vpc.securityGroup 으로 지정.
# unicorn-mark(CloudShell) 에서 private API(443) 에 곧바로 접근 가능하게 한다.
resource "aws_security_group" "eks_cp_extra" {
  name        = "unicorn-eks-cp-extra-sg"
  description = "Extra control plane SG - allow unicorn-mark to reach private API (443)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS to EKS API from unicorn-mark CloudShell"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.mark.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "unicorn-eks-cp-extra-sg" }
}
