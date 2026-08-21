# vpc-endpoints 부착 스니펫

Gateway(S3·DynamoDB) + Interface(PrivateLink) 엔드포인트 묶음. 1과제 Security 옵션
("private 서브넷에서 인터넷 경유 없이 ECR/로그/S3 접근", set-02/07/09 task-1, set-08 task-1 채점 1-5)과
set-02 task-2 m4 후보에 대응한다.

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `endpoints.tf` — Gateway 엔드포인트(for_each) · Interface 엔드포인트(for_each, private DNS) · 엔드포인트 SG(443 from VPC CIDR)
- `variables.tf` — `addon_vpce_*` 변수. 서비스 목록·라우트 테이블·서브넷은 tfvars 로 주입

## 부착 절차

1. `endpoints.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다.
2. `terraform.tfvars` 에 값을 넣는다. 기존 리소스를 직접 참조하려면 `var.addon_vpce_vpc_id` 를 `aws_vpc.<기존>.id`, `var.addon_vpce_route_table_ids` 를 `aws_route_table.private[*].id`, `var.addon_vpce_subnet_ids` 를 `aws_subnet.private[*].id` 로 바꾼다.

   ```hcl
   addon_vpce_vpc_id          = "vpc-0123456789abcdef0"
   addon_vpce_vpc_cidr        = "10.0.0.0/16"
   addon_vpce_route_table_ids = ["rtb-0a...", "rtb-0b..."]       # private RTB
   addon_vpce_subnet_ids      = ["subnet-0a...", "subnet-0b..."] # private 서브넷, AZ 당 1개
   addon_vpce_gateway_services   = ["s3", "dynamodb"]
   addon_vpce_interface_services = ["ecr.api", "ecr.dkr", "logs", "sts"]
   addon_vpce_name_prefix = "skills-vpce"
   addon_vpce_sg_name     = "skills-vpce-sg"
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=<VPC ID> --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State,PrivateDnsEnabled]' --output table
   ```

## 블록

### 서비스별 필요한 Interface 엔드포인트 (짧은 이름)

| 용도 | 서비스 |
| --- | --- |
| ECR pull (EKS/ECS private) | `ecr.api`, `ecr.dkr` + Gateway `s3` (레이어는 S3 에서 받는다) |
| CloudWatch Logs / 메트릭 | `logs`, `monitoring` |
| IRSA·Pod Identity·AssumeRole | `sts` |
| Secrets Manager / SSM Parameter | `secretsmanager`, `ssm` |
| SSM Session Manager | `ssm`, `ssmmessages`, `ec2messages` |
| SNS / SQS | `sns`, `sqs` |
| KMS | `kms` |

### 엔드포인트 정책 제한 (과제지가 "특정 버킷만" 을 요구할 때)

```hcl
# aws_vpc_endpoint.addon_gateway 리소스 안에:
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = "*"
    Action    = ["s3:GetObject", "s3:ListBucket"]
    Resource  = ["arn:aws:s3:::<버킷>", "arn:aws:s3:::<버킷>/*"]
  }]
})
```

## 함정

- 전부 신규 리소스 — 기존 리소스 재생성 없음. Gateway 의 `route_table_ids` 변경은 in-place, `service_name`·`vpc_endpoint_type` 변경은 ⚠ 재생성.
- Gateway 는 **s3·dynamodb 만**. 다른 서비스를 `addon_vpce_gateway_services` 에 넣으면 apply 실패.
- `private_dns_enabled = true` 는 VPC 의 `enable_dns_support`·`enable_dns_hostnames` 가 둘 다 true 여야 한다 — 아니면 apply 에서 InvalidParameter.
- **`eks`·`eks-auth` Interface 엔드포인트를 private DNS 로 만들지 말 것** — `oidc.eks.*` 조회가 NXDOMAIN 이 되어 IRSA 전체가 깨진다(set-05 task-1 NOTES 실측).
- S3 **Interface** 엔드포인트는 private DNS 활성 시 S3 Gateway 엔드포인트를 같이 요구한다. "라우트 테이블에 규칙을 둘 수 없다" 류 제약이면 set-05 task-1 의 Route53 PHZ 패턴을 쓴다.
- Interface 엔드포인트는 같은 AZ 에 서브넷 하나만 — 같은 AZ 서브넷 둘을 넣으면 DuplicateSubnetsInSameZone.
- 채점 스크립트는 `ServiceName = com.amazonaws.<region>.<svc>` 문자열·`VpcEndpointType` 을 정확히 읽는다(set-08 task-1 채점 1-5). 리전은 provider 리전에서 자동 조립된다.
- Interface 엔드포인트는 시간당 과금 — 과제지가 요구하는 서비스만 목록에 남긴다(불필요 리소스 감점).

## 실전 구현 (참고용)

- set-07 task-1 `terraform/endpoints.tf` — S3 Gateway + ecr.api/ecr.dkr/logs Interface
- set-05 task-1 `terraform/endpoints.tf` — Interface 11종 + S3/DynamoDB Interface + Route53 PHZ 매핑
- set-08 task-1 `terraform/vpc.tf` — DynamoDB Gateway (채점 1-5)
