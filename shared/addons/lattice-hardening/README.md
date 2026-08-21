# lattice-hardening 부착 스니펫

기존 VPC Lattice 서비스에 IAM 인증·액세스 로그·헤더 기반 라우팅·SG 제한을 얹는다.
2과제 Lattice 모듈(set-05 task-2 module-2-vpc-lattice, set-08 task-2 module-2-lattice) 의 당일 추가 문항
("서비스에 IAM 인증 적용", "액세스 로그를 CloudWatch/S3 로", "version 헤더로 v1/v2 분기 + 가중치", "Lattice 경유 외 접근 차단") 에 대응한다.

## 파일

- `lattice-hardening.tf` — `aws_vpclattice_auth_policy` · 액세스 로그 그룹 + `aws_vpclattice_access_log_subscription`(CW 기본, S3 선택) · `aws_vpclattice_listener_rule` 2개(header `version: v1/v2`, `addon_lattice_listener_id` 가 비어 있으면 생성 안 함)
- `variables.tf` — `addon_lattice_*` 변수. 서비스·리스너·TG ID 는 기존 리소스를 변수로 받는다

기존 리소스 **안에** 넣는 인자(`auth_type`, association SG, TG 타입, 서비스 SG)는 아래 "블록" 절.

## 부착 절차

1. `lattice-hardening.tf`·`variables.tf` 를 `set-XX/task-2/module-N-lattice/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 같은 state 의 리소스를 직접 참조하려면 `var.addon_lattice_service_id` 를 `aws_vpclattice_service.this.id`, `var.addon_lattice_listener_id` 를 `aws_vpclattice_listener.http.listener_id`, TG ID 를 `aws_vpclattice_target_group.v1.id` 등으로 바꾼다.

   ```hcl
   addon_lattice_service_id          = "svc-0123456789abcdef0"
   addon_lattice_service_name        = "wsc-app-service"
   addon_lattice_auth_principal_arns = ["arn:aws:iam::123456789012:role/wsc-hub-client-role"]   # 비우면 계정 내 전체 허용
   addon_lattice_log_s3_bucket_arn   = ""                                                      # S3 로그 요구 시 버킷 ARN
   # 헤더 룰이 요구될 때만
   addon_lattice_listener_id         = "listener-0123456789abcdef0"
   addon_lattice_v1_target_group_id  = "tg-0123456789abcdef1"
   addon_lattice_v2_target_group_id  = "tg-0123456789abcdef2"
   addon_lattice_rule_priority_base  = 10
   ```

3. 아래 "블록" 중 과제지가 요구한 것을 기존 리소스 안에 추가한다. IAM 인증 문항이면 `auth_type = "AWS_IAM"` 블록은 **필수**(정책만 붙이면 효과 없음).
4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스가 update in-place 인지 확인한다 (Lattice 리소스는 이 스니펫 범위에서 재생성이 없다).
5. `terraform apply`. 확인: `aws vpc-lattice get-auth-policy --resource-identifier <svc>`, `aws vpc-lattice list-access-log-subscriptions --resource-identifier <svc>`, `aws vpc-lattice list-rules --service-identifier <svc> --listener-identifier <listener>`.

## 블록

### 서비스 IAM 인증 (in-place)

```hcl
# aws_vpclattice_service 리소스 안에:
auth_type = "AWS_IAM"
```

서비스 네트워크에도 걸라면 `aws_vpclattice_service_network` 에 같은 인자 + `aws_vpclattice_auth_policy` 를 `resource_identifier = aws_vpclattice_service_network.this.id` 로 하나 더 만든다.

### 가중 라우팅 (리스너 default_action, in-place)

```hcl
# aws_vpclattice_listener 리소스 안의 default_action:
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
```

헤더 룰(priority 10/20) 이 default 보다 먼저 평가되므로 "헤더 있으면 고정, 없으면 가중" 이 된다.

### Service Network ↔ VPC association SG (in-place)

```hcl
# aws_vpclattice_service_network_vpc_association 리소스 안에:
security_group_ids = [aws_security_group.sn_assoc.id]

# SG 는 클라이언트 VPC 에 두고 ingress 는 클라이언트 CIDR → 리스너 포트만:
resource "aws_security_group" "sn_assoc" {
  name   = "<sn-name>-assoc-sg"
  vpc_id = aws_vpc.client.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.client_vpc_cidr]
  }
}
```

### 대상 그룹 타입

```hcl
# INSTANCE 타입 (EC2 직접, set-08):
resource "aws_vpclattice_target_group" "svc" {
  name = "<tg-name>"
  type = "INSTANCE"
  config {
    vpc_identifier = aws_vpc.service.id
    port           = 8080
    protocol       = "HTTP"
    health_check {
      enabled  = true
      path     = "/health"
      protocol = "HTTP"
      port     = 8080
    }
  }
}

# ALB 타입 (internal ALB 앞단, set-05) — health_check 블록 불가, protocol_version 필수:
resource "aws_vpclattice_target_group" "alb" {
  name = "<tg-name>"
  type = "ALB"
  config {
    port             = 80
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = aws_vpc.spoke.id
  }
}

resource "aws_vpclattice_target_group_attachment" "alb" {
  target_group_identifier = aws_vpclattice_target_group.alb.id
  target {
    id   = aws_lb.app.arn
    port = 80
  }
}
```

### 서비스 측 SG — Lattice managed prefix list 만 허용

```hcl
data "aws_ec2_managed_prefix_list" "addon_lattice" {
  name = "com.amazonaws.${var.region}.vpc-lattice"
}

# 서비스 EC2/ALB SG 의 ingress 를 0.0.0.0/0 대신:
ingress {
  from_port       = 8080
  to_port         = 8080
  protocol        = "tcp"
  prefix_list_ids = [data.aws_ec2_managed_prefix_list.addon_lattice.id]
}
```

클라이언트 SG egress 도 같은 prefix list + 리스너 포트만으로 좁힐 수 있다 (set-08 `sg.tf`).

## 함정

- **재생성 없음**: `auth_type`·auth policy·로그 구독·리스너 룰·association SG 는 전부 in-place. TG `type`·`config` 변경만 ⚠ 재생성.
- `auth_type = "AWS_IAM"` 뒤에는 클라이언트가 **SigV4 서명**을 해야 한다 — 평범한 `curl` 은 403. 채점 스크립트가 익명 curl 로 확인하는 항목이 있으면 충돌한다. 과제지 요구 범위를 먼저 확인한다. 테스트는 `awscurl --service vpc-lattice-svcs --region <리전> <URL>` 또는 SDK.
- auth policy 의 `principals = ["*"]` 는 `aws:PrincipalAccount` 조건이 있어야 "인증된 계정 내 principal" 이 된다 — 조건 없이 `*` 면 익명도 허용돼 IAM 인증 의미가 없다. 스니펫은 ARN 목록이 비면 자동으로 조건을 건다.
- 서비스 네트워크 `auth_type = AWS_IAM` 에 정책을 안 붙이면 그 SN 의 모든 서비스가 거부된다.
- 액세스 로그 구독은 대상 타입(CW Logs / S3 / Firehose)당 리소스당 1개. 같은 타입 2개는 생성 거부.
- 서비스 SG 에 `0.0.0.0/0` 이 있으면 set-08 과제지가 **명시적으로 미충족** 처리한다 — prefix list 만 남긴다. prefix list 이름은 리전별 `com.amazonaws.<region>.vpc-lattice`.
- 헤더 룰 `priority` 는 리스너 안에서 유일해야 한다. 기존 룰이 있으면 `addon_lattice_rule_priority_base` 를 비켜 둔다. ALB 타입 TG 로 보낼 때 ALB 리스너 룰도 같은 헤더를 다시 보고 분기해야 한다 (set-05 `alb.tf`).
- 서비스·TG·리스너 이름은 채점 스크립트가 name 으로 조회한다 (set-08 2-3·2-4). 기존 이름을 바꾸지 않는다.
- 리소스 정책·로그 구독의 `resource_identifier` 는 ID 와 ARN 둘 다 받는다. 서비스 ID 는 `aws vpc-lattice list-services --query 'items[?name==`<이름>`].id'`.

## 실전 구현 (참고용)

- `set-05/task-2/module-2-vpc-lattice/terraform/lattice.tf` — ALB 타입 TG · 헤더 룰 v1/v2 · 가중 default_action
- `set-05/task-2/module-2-vpc-lattice/terraform/alb.tf` — Lattice 뒤 internal ALB 헤더 분기, ALB SG prefix list
- `set-08/task-2/module-2-lattice/terraform/lattice.tf` — INSTANCE 타입 TG · association SG
- `set-08/task-2/module-2-lattice/terraform/sg.tf` — Lattice managed prefix list 기반 SG 3종
- auth policy·액세스 로그 실전 구현: 없음
