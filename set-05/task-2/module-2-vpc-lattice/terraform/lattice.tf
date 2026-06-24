# ---------------------------------------------------------------------------
# VPC Lattice (과제지 4. VPC Lattice - VPC Lattice 구성)
# - Service Network: wsc-app-service-network (hub + spoke VPC 모두 연결)
# - Service: wsc-app-service
# - Target Group(type ALB): wsc-spoke-v1-tg / wsc-spoke-v2-tg -> Internal ALB:80
# - Listener(HTTP 80):
#     Default Rule(99999)         : v1 90% / v2 10% 가중 라우팅
#     Header Rule(priority 10)    : version=v1 -> wsc-spoke-v1-tg (weight 100)
#     Header Rule(priority 20)    : version=v2 -> wsc-spoke-v2-tg (weight 100)
#   Header 기반 라우팅이 Weighted 보다 우선(priority 10/20 < 99999).
# 모든 Hub->Spoke 통신은 Lattice 를 경유한다 (직접 Peering/Private IP 접근 없음).
# ---------------------------------------------------------------------------

resource "aws_vpclattice_service_network" "this" {
  name      = "wsc-app-service-network"
  auth_type = "NONE"

  tags = { Name = "wsc-app-service-network" }
}

resource "aws_vpclattice_service" "this" {
  name      = "wsc-app-service"
  auth_type = "NONE"

  tags = { Name = "wsc-app-service" }
}

resource "aws_vpclattice_service_network_service_association" "this" {
  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

# ----- Service Network <-> VPC 연결 (hub + spoke) -----
resource "aws_vpclattice_service_network_vpc_association" "hub" {
  vpc_identifier             = aws_vpc.hub.id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

resource "aws_vpclattice_service_network_vpc_association" "spoke" {
  vpc_identifier             = aws_vpc.spoke.id
  service_network_identifier = aws_vpclattice_service_network.this.id
}

# ----- Lattice Target Group (type ALB) -> Internal ALB:80 -----
resource "aws_vpclattice_target_group" "v1" {
  name = "wsc-spoke-v1-tg"
  type = "ALB"

  config {
    port             = 80
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = aws_vpc.spoke.id
  }

  tags = { Name = "wsc-spoke-v1-tg" }
}

resource "aws_vpclattice_target_group" "v2" {
  name = "wsc-spoke-v2-tg"
  type = "ALB"

  config {
    port             = 80
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = aws_vpc.spoke.id
  }

  tags = { Name = "wsc-spoke-v2-tg" }
}

resource "aws_vpclattice_target_group_attachment" "v1" {
  target_group_identifier = aws_vpclattice_target_group.v1.id
  target {
    id   = aws_lb.app.arn
    port = 80
  }
}

resource "aws_vpclattice_target_group_attachment" "v2" {
  target_group_identifier = aws_vpclattice_target_group.v2.id
  target {
    id   = aws_lb.app.arn
    port = 80
  }
}

# ----- Listener (HTTP 80) : Default = 가중 라우팅 -----
resource "aws_vpclattice_listener" "http" {
  name               = "wsc-app-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.this.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v1.id
        weight                  = 90
      }
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v2.id
        weight                  = 10
      }
    }
  }
}

# ----- Header Rule: version=v1 (priority 10) -----
resource "aws_vpclattice_listener_rule" "v1" {
  name                = "version-v1"
  listener_identifier = aws_vpclattice_listener.http.listener_id
  service_identifier  = aws_vpclattice_service.this.id
  priority            = 10

  match {
    http_match {
      header_matches {
        name           = "version"
        case_sensitive = false
        match {
          exact = "v1"
        }
      }
    }
  }

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v1.id
        weight                  = 100
      }
    }
  }
}

# ----- Header Rule: version=v2 (priority 20) -----
resource "aws_vpclattice_listener_rule" "v2" {
  name                = "version-v2"
  listener_identifier = aws_vpclattice_listener.http.listener_id
  service_identifier  = aws_vpclattice_service.this.id
  priority            = 20

  match {
    http_match {
      header_matches {
        name           = "version"
        case_sensitive = false
        match {
          exact = "v2"
        }
      }
    }
  }

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.v2.id
        weight                  = 100
      }
    }
  }
}
