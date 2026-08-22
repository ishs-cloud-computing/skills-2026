# VPC 엔드포인트 부착 KIT

Gateway(S3·DynamoDB) + Interface(PrivateLink) 엔드포인트 묶음.

## 이 KIT이 맞나

- 과제지에 **"private 서브넷에서 인터넷 경유 없이 ECR/로그/S3 접근"·"PrivateLink"·"VPC 엔드포인트"** → 맞다.
- **DynamoDB 엔드포인트 하나만** → [dynamodb-hardening](../dynamodb-hardening/README.md) 7번으로도 된다.
- 전부 신규 리소스라 기존 리소스 재생성이 없다.

## 세트별 현재 엔드포인트

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| Gateway S3 | **없음** | `aws_vpc_endpoint.s3` | `aws_vpc_endpoint.s3` |
| Gateway DynamoDB | **없음** | **없음** | **없음** |
| Interface | **없음** | **없음** | `aws_vpc_endpoint.interface` (for_each) + `aws_security_group.vpce` |
| 프라이빗 라우트 테이블 | `aws_route_table.private[k]` (for_each) | `aws_route_table.app[k]` (for_each) | `aws_route_table.private[k]` (for_each) |
| 파일 | 없음 (`vpc.tf` 만) | `endpoints.tf` | `endpoints.tf` |
| `vpc_id` output | 있음 | 있음 | 있음 |
| `private_subnet_ids` output | 있음 (map) | 있음 (map) | 있음 (map) |

**세 세트 모두 라우트 테이블이 `for_each` 맵이다** — `aws_route_table.private.id` 가 아니라 `[for k in local.private_subnet_keys : aws_route_table.private[k].id]` 로 참조한다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `endpoints.tf` | `set-XX/task-1/terraform/endpoints-addon.tf` (set-03·set-07은 `endpoints.tf` 가 이미 있다) | Gateway(for_each) · Interface(for_each, private DNS) · 엔드포인트 SG(443 from VPC CIDR) |
| `variables.tf` | `variables-vpce-addon.tf` | `addon_vpce_*` 변수 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_vpce_vpc_id` | **필수** | 직접 참조 권장 (`aws_vpc.this.id`) |
| `addon_vpce_vpc_cidr` | **필수** | Interface SG의 443 허용 소스 CIDR |
| `addon_vpce_route_table_ids` | `[]` | Gateway를 연결할 private 라우트 테이블 목록 |
| `addon_vpce_subnet_ids` | `[]` | Interface ENI를 둘 private 서브넷 (**AZ당 1개**) |
| `addon_vpce_gateway_services` | `["s3", "dynamodb"]` | **s3 / dynamodb만 Gateway를 지원한다** |
| `addon_vpce_interface_services` | `["ecr.api", "ecr.dkr", "logs"]` | Interface 짧은 이름 목록. 빈 목록이면 SG도 안 만든다 |
| `addon_vpce_name_prefix` | `"vpce"` | Name 태그 접두 (`<prefix>-<service>`) |
| `addon_vpce_sg_name` | `"vpce-sg"` | Interface SG 이름 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply
```

## 1. Gateway 엔드포인트 (S3 · DynamoDB)

```hcl
# 파일: set-XX/task-1/terraform/endpoints-addon.tf   (KIT에서 복사됨)
resource "aws_vpc_endpoint" "addon_gateway" {
  for_each          = toset(var.addon_vpce_gateway_services)
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for k in local.private_subnet_keys : aws_route_table.private[k].id]   # ← set-03 은 .app[k]
  tags              = { Name = "${var.addon_vpce_name_prefix}-${each.key}" }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 라우트 테이블 참조 | 이미 있는 Gateway |
| --- | --- | --- |
| set-02 | `[for k in local.private_subnet_keys : aws_route_table.private[k].id]` | 없음 — S3·DynamoDB 둘 다 새로 |
| set-03 | `[for k in local.private_subnet_keys : aws_route_table.app[k].id]` | `s3` — DynamoDB만 추가 |
| set-07 | `[for k in local.private_subnet_keys : aws_route_table.private[k].id]` | `s3` — DynamoDB만 추가 |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "private_route_table_ids" {
  value = { for k in local.private_subnet_keys : k => aws_route_table.private[k].id }   # set-03 은 .app[k]
}
output "gateway_endpoint_ids" {
  value = { for k, v in aws_vpc_endpoint.addon_gateway : k => v.id }
}
```

```powershell
terraform output -raw vpc_id                 # 세 세트 모두 있음
terraform output -json private_route_table_ids
terraform output -json gateway_endpoint_ids

aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" `
  --query "VpcEndpoints[].[ServiceName,VpcEndpointType,State,RouteTableIds]" --output table

# 라우트 테이블에 prefix list 경로가 실제로 박혔는지
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" `
  --query "RouteTables[].Routes[?DestinationPrefixListId].[DestinationPrefixListId,GatewayId]"
```

**Gateway는 s3·dynamodb만** 지원한다. 다른 서비스를 넣으면 apply가 실패한다.
</details>

## 2. Interface 엔드포인트 (PrivateLink)

```hcl
# 파일: set-XX/task-1/terraform/endpoints-addon.tf   (KIT에서 복사됨)
resource "aws_vpc_endpoint" "addon_interface" {
  for_each            = toset(var.addon_vpce_interface_services)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for k in local.private_subnet_keys : aws_subnet.this[k].id]   # AZ당 1개
  security_group_ids  = [aws_security_group.addon_vpce.id]
  private_dns_enabled = true
  tags                = { Name = "${var.addon_vpce_name_prefix}-${each.key}" }
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 이미 있는 Interface | SG |
| --- | --- | --- |
| set-02 | 없음 | 새로 만든다 |
| set-03 | 없음 | 새로 만든다 |
| set-07 | `aws_vpc_endpoint.interface` (for_each) **있음** | `aws_security_group.vpce` **있음** — 재사용 |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "interface_endpoint_dns" {
  value = { for k, v in aws_vpc_endpoint.addon_interface : k => v.dns_entry[0].dns_name }
}
output "vpce_sg_id" { value = aws_security_group.addon_vpce.id }
```

```powershell
terraform output -json private_subnet_ids     # 세 세트 모두 있음 (map)
terraform output -json interface_endpoint_dns
terraform output -raw vpce_sg_id

aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" `
  "Name=vpc-endpoint-type,Values=Interface" `
  --query "VpcEndpoints[].[ServiceName,State,PrivateDnsEnabled,SubnetIds]" --output table

# 노드/Pod 안에서 실제로 private IP 로 풀리는지 (이게 최종 확인이다)
kubectl run dnstest --rm -it --image=busybox --restart=Never -- nslookup api.ecr.ap-northeast-2.amazonaws.com
```

**Interface 엔드포인트는 같은 AZ에 서브넷 하나만** 넣는다 — 같은 AZ 둘이면 `DuplicateSubnetsInSameZone`.
</details>

## 3. 서비스별 필요한 Interface 엔드포인트

| 용도 | 서비스 짧은 이름 |
| --- | --- |
| ECR pull (EKS private) | `ecr.api`, `ecr.dkr` + **Gateway `s3`** (레이어는 S3에서 받는다) |
| CloudWatch Logs / 메트릭 | `logs`, `monitoring` |
| IRSA·Pod Identity·AssumeRole | `sts` |
| Secrets Manager / SSM Parameter | `secretsmanager`, `ssm` |
| SSM Session Manager (bastion) | `ssm`, `ssmmessages`, `ec2messages` |
| SNS / SQS | `sns`, `sqs` |
| KMS | `kms` |

<details><summary><b>값 뽑기 — 세트별 (무엇이 필요한지 판정)</b></summary>

| 세트 | 최소 필요 | 이유 |
| --- | --- | --- |
| set-02 | `ecr.api` `ecr.dkr` + Gateway `s3`, `logs`, `sts` | IRSA(`sts`) · Fluent Bit(`logs`) · 이미지 pull |
| set-03 | `ecr.api` `ecr.dkr`, `logs` (+ `ssm` `ssmmessages` `ec2messages` — bastion SSM) | Pod Identity라 `sts` 불필요. bastion이 SSM 접속이다 |
| set-07 | 이미 `ecr.api` `ecr.dkr` `logs` 구성됨 | 추가 요구 시 목록에만 더한다 |

```powershell
# NAT 없이 되는지 확인 — Pod 에서 ECR pull
kubectl get events -A --field-selector reason=Failed | Select-String -Pattern "ErrImagePull|ImagePullBackOff"
kubectl describe pod <파드> -n <ns> | Select-String -Pattern "Failed to pull"

# 로그가 실제로 나가는지
aws logs tail (terraform output -raw app_log_group) --since 5m
```

**Interface 엔드포인트는 시간당 과금**이다 — 과제지가 요구하는 서비스만 남긴다(불필요 리소스 감점).
</details>

## 4. 엔드포인트 정책 제한 ("특정 버킷만")

```hcl
# 파일: set-XX/task-1/terraform/endpoints-addon.tf
# 기존 aws_vpc_endpoint 리소스 블록 *안에*
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = "*"
    Action    = ["s3:GetObject", "s3:ListBucket"]
    Resource = [
      "arn:aws:s3:::${aws_s3_bucket.web.id}",       # ← 세트별 주소
      "arn:aws:s3:::${aws_s3_bucket.web.id}/*",
    ]
  }]
})
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
terraform output -raw s3_bucket_name    # 세 세트 모두 있음

$vpce = (aws ec2 describe-vpc-endpoints `
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" "Name=service-name,Values=com.amazonaws.ap-northeast-2.s3" `
  --query "VpcEndpoints[0].VpcEndpointId" --output text)
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $vpce --query "VpcEndpoints[0].PolicyDocument" --output text
```

정책을 좁히면 **ECR 레이어 pull도 막힌다** — ECR용 S3 버킷(`prod-<region>-starport-layer-bucket`)을 같이 허용하거나, 정책을 걸지 않는다.
</details>

## VERIFY

```powershell
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" `
  --query "VpcEndpoints[].[ServiceName,VpcEndpointType,State,PrivateDnsEnabled]" --output table
```

## TROUBLESHOOT

- Gateway의 `route_table_ids` 변경은 in-place, `service_name`·`vpc_endpoint_type` 변경은 **재생성**이다.
- **Gateway는 s3·dynamodb만.**
- `private_dns_enabled = true` 는 VPC의 `enable_dns_support`·`enable_dns_hostnames` 가 둘 다 true여야 한다 — 아니면 `InvalidParameter`.
- **`eks`·`eks-auth` Interface 엔드포인트를 private DNS로 만들지 말 것** — `oidc.eks.*` 조회가 NXDOMAIN이 되어 IRSA 전체가 깨진다(set-05 task-1 NOTES 실측). set-03 `endpoints.tf` 주석에도 같은 경고가 있다.
- S3 **Interface** 엔드포인트는 private DNS 활성 시 S3 Gateway 엔드포인트를 같이 요구한다.
- Interface는 같은 AZ에 서브넷 하나만 — 아니면 `DuplicateSubnetsInSameZone`.
- 채점은 `ServiceName = com.amazonaws.<region>.<svc>` 문자열·`VpcEndpointType` 을 정확히 읽는다.
- Interface 엔드포인트는 시간당 과금이다.

## 실전 구현 (참고용)

- set-07 task-1 `terraform/endpoints.tf` — S3 Gateway + `ecr.api`/`ecr.dkr`/`logs` Interface + `aws_security_group.vpce`
- set-03 task-1 `terraform/endpoints.tf` — S3 Gateway (+ eks private DNS 경고 주석)
- set-05 task-1 `terraform/endpoints.tf` — Interface 11종 + S3/DynamoDB Interface + Route53 PHZ 매핑
- set-08 task-1 `terraform/vpc.tf` — DynamoDB Gateway

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
