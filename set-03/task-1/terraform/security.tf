# ---------------------------------------------------------------------------
# Security Groups
# - wsc2026-app-alb-sg         : CloudFront origin-facing prefix list → ALB(80).
#                                직접 접근은 차단 (mark 8-1: curl → 000/BLOCKED)
# - wsc2026-eks-shared-node-sg : ALB → Pod(8080) 사전 허용 (노드에 attach).
#                                ingress 에 security-groups 로 ALB SG 를 단독 지정하면
#                                LBC 가 백엔드 규칙을 만들지 않으므로 여기서 미리 연다.
# - wsc2026-eks-cp-extra-sg    : mark-sg(CloudShell) → EKS private API(443)
# - wsc2026-mark-sg            : 채점용 CloudShell VPC Environment SG (채점 유의 10·11)
# 유의사항 6: 80/443 Outbound any-open 허용 → 전체 egress 로 충족.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "wsc2026-app-alb-sg"
  description = "wsc2026-app-alb - allow 80 from CloudFront origin-facing only"
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
  tags = { Name = "wsc2026-app-alb-sg" }
}

# 노드에 직접 attach 하는 공용 SG. ingress 어노테이션에 wsc2026-app-alb-sg 를
# 단독 지정(manage-backend-security-group-rules 미사용 — mark 8-1 이 ALB SG 이름
# 단독 출력을 요구)하므로, ALB → Pod(8080) target/health check 를 사전 허용한다.
resource "aws_security_group" "eks_shared_node" {
  name        = "wsc2026-eks-shared-node-sg"
  description = "Shared node SG - allow ALB to reach Book App Pod (8080)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "wsc2026-app-alb to Book App Pod (8080)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wsc2026-eks-shared-node-sg" }
}

# 채점용 CloudShell VPC Environment 가 사용할 SG (채점 유의 10: 선수 임의 구성).
resource "aws_security_group" "mark" {
  name        = "mark-sg"
  description = "CloudShell VPC environment SG for marking"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "mark-sg" }
}

# EKS Control Plane 추가 SG: cluster.yaml 의 vpc.securityGroup 으로 지정.
# Fully private API 에 CloudShell(mark-sg)이 접근할 수 있게 한다.
resource "aws_security_group" "eks_cp_extra" {
  name        = "wsc2026-eks-cp-extra-sg"
  description = "Extra control plane SG - allow mark-sg to reach private API (443)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS to EKS API from mark CloudShell"
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
  tags = { Name = "wsc2026-eks-cp-extra-sg" }
}
