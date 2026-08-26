# lattice-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 VPC Lattice 서비스에 IAM 인증·액세스 로그·헤더 기반 라우팅·SG 제한을 얹는다.
2과제 Lattice 모듈(set-05 task-2 module-2-vpc-lattice, set-08 task-2 module-2-lattice) 의 당일 추가 문항
("서비스에 IAM 인증 적용", "액세스 로그를 CloudWatch/S3 로", "version 헤더로 v1/v2 분기 + 가중치", "Lattice 경유 외 접근 차단") 에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_lattice_service_id` | **필수** | 기존 VPC Lattice 서비스 ID(svc-...) 또는 ARN. 같은 state 면 aws_vpclattice_service.this.id 로 바꾼다 |
| `addon_lattice_service_name` | `"wsc-app-service"` | 기존 서비스 이름. 로그 그룹 이름 접두로 쓴다 |
| `addon_lattice_auth_principal_arns` | `[]` | Invoke 를 허용할 IAM principal ARN 목록. 비어 있으면 같은 계정의 모든 인증된 principal 허용 |
| `addon_lattice_log_retention_days` | `7` | 액세스 로그 그룹 보존 일수 |
| `addon_lattice_log_s3_bucket_arn` | `""` | S3 로도 액세스 로그를 보내려면 버킷 ARN. 빈 문자열이면 CloudWatch Logs 만 |
| `addon_lattice_listener_id` | `""` | 기존 리스너 ID(listener-...). 같은 state 면 aws_vpclattice_listener.http.listener_id 로 바꾼다. 빈 문자열이면 룰을 만들지 않는다 |
| `addon_lattice_header_name` | `"version"` | 라우팅 기준 헤더 이름 |
| `addon_lattice_v1_target_group_id` | `""` | v1 대상 그룹 ID(tg-...). 같은 state 면 aws_vpclattice_target_group.v1.id |
| `addon_lattice_v2_target_group_id` | `""` | v2 대상 그룹 ID(tg-...). 같은 state 면 aws_vpclattice_target_group.v2.id |
| `addon_lattice_rule_priority_base` | `10` | 헤더 룰 priority 시작값 (v1 = base, v2 = base+10). 기존 룰과 겹치지 않게 |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

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

## TROUBLESHOOT — 이 KIT 고유 함정
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

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
