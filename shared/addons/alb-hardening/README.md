# ALB 강화 부착 KIT

기존 ALB에 액세스 로그 · 삭제 보호 · 헤더 검증 리스너 규칙 · HTTPS 리스너를 붙인다.

## 이 KIT이 맞나

- 과제지 기존 로드밸런서 문항 뒤에 **"액세스 로그를 S3에"·"삭제 보호"·"리스너 규칙"·"HTTP→HTTPS"** 가 붙었다 → 맞다.
- **set-03에는 Terraform ALB가 없다.** LBC가 Ingress로 만든다 — 이 KIT의 Terraform 블록이 안 맞는다. 아래 4번(어노테이션)을 본다.

## 세트별 현재 ALB 구성

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 앱 ALB | `aws_lb.book` (internet-facing) | **없음** — k8s Ingress(LBC) | `aws_lb.app` (**internal** + CloudFront VPC Origin) |
| Grafana ALB | `aws_lb.grafana` | 없음 (Ingress 경로) | `aws_lb.grafana` |
| 리스너 | `aws_lb_listener.book` (80) | Ingress annotation | `aws_lb_listener.app` (80) |
| 리스너 규칙 | `.book_post` · `.book_lambda` (헤더 조건) | — | `.health`(10) · `.post`(20) |
| 타깃 그룹 | `.book` · `.lambda` · `.grafana` | LBC 생성 | `.app` · `.lambda` · `.grafana` |
| DNS output | `book_alb_dns` · `grafana_alb_dns` | **없음** | `alb_dns_name` · `grafana_alb_dns_name` |
| TG ARN output | `app_target_group_arn` · `grafana_target_group_arn` | **없음** | `app_target_group_arn` · `grafana_target_group_arn` |
| ALB ARN output | **없음** | — | **없음** |
| 액세스 로그 | **없음** | 없음 | **없음** |
| 삭제 보호 | **없음** | 없음 | **없음** |

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `alb-hardening.tf` | `set-XX/task-1/terraform/` | 로그 버킷(SSE-S3) + 버킷 정책 · 헤더 조건 리스너 규칙(count) · HTTPS 리스너(count) |
| `variables.tf` | `variables-albh-addon.tf` | `addon_albh_*` 변수 |

로그만 필요하면 리스너 규칙·HTTPS 리소스 블록은 지워도 된다 (변수 기본값이 `""` 라 count 0으로도 안 생긴다).

`access_logs` · `enable_deletion_protection` · `drop_invalid_header_fields` 는 파일이 아니라 기존 `aws_lb` 안에 넣는 **인자**다.

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_albh_log_bucket_prefix` | `"skills-alb-logs"` | 로그 버킷 접두. 뒤에 `-<account_id>` |
| `addon_albh_log_prefix` | `"alb"` | `access_logs.prefix`. **끝에 `/` 를 넣지 않는다** |
| `addon_albh_listener_arn` | `""` | 규칙을 붙일 기존 HTTP 리스너 ARN. 직접 참조 권장 |
| `addon_albh_target_group_arn` | `""` | 규칙·HTTPS 리스너가 forward할 타깃 그룹 ARN |
| `addon_albh_rule_priority` | `1` | 규칙 priority. 기존 규칙과 겹치지 않게 |
| `addon_albh_header_name` | `"X-Origin-Verify"` | 오리진 검증 헤더 이름 |
| `addon_albh_header_value` | `""` | CloudFront `custom_header.value` 와 **바이트 단위 동일** |
| `addon_albh_alb_arn` | `""` | HTTPS 리스너를 붙일 ALB ARN |
| `addon_albh_certificate_arn` | `""` | ACM ARN (**ALB와 같은 리전**). 빈 문자열이면 HTTPS 리스너 생성 안 함 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan        # aws_lb 가 update in-place 인지 확인
terraform apply
```

## 1. 액세스 로그 · 삭제 보호 · 잘못된 헤더 드롭

```hcl
# 파일: set-XX/task-1/terraform/alb.tf
# 기존 aws_lb 리소스 블록 *안에* (전부 in-place)
access_logs {
  bucket  = aws_s3_bucket.addon_alb_logs.id
  prefix  = var.addon_albh_log_prefix
  enabled = true
}

enable_deletion_protection = true
drop_invalid_header_fields = true

# 버킷 정책이 먼저 있어야 access_logs 적용이 성공한다
depends_on = [aws_s3_bucket_policy.addon_alb_logs]
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 붙일 `aws_lb` | ALB ARN output |
| --- | --- | --- |
| set-02 | `aws_lb.book` (+ 요구되면 `aws_lb.grafana` 도) | **없음** — 아래 블록 추가 |
| set-03 | **Terraform ALB 없음** — 4번(어노테이션)으로 | — |
| set-07 | `aws_lb.app` (+ `aws_lb.grafana`) | **없음** — 아래 블록 추가 |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_alb_arn"     { value = aws_lb.book.arn }
output "grafana_alb_arn" { value = aws_lb.grafana.arn }
output "alb_log_bucket"  { value = aws_s3_bucket.addon_alb_logs.id }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_alb_arn"     { value = aws_lb.app.arn }
output "grafana_alb_arn" { value = aws_lb.grafana.arn }
output "alb_log_bucket"  { value = aws_s3_bucket.addon_alb_logs.id }
```

```powershell
$alb = terraform output -raw app_alb_arn
aws elbv2 describe-load-balancer-attributes --load-balancer-arn $alb `
  --query "Attributes[?starts_with(Key,'access_logs') || Key=='deletion_protection.enabled' || Key=='routing.http.drop_invalid_header_fields.enabled']"

# 로그는 5분 주기. 첫 파일은 ELBAccessLogTestFile
aws s3 ls "s3://$(terraform output -raw alb_log_bucket)/alb/AWSLogs/" --recursive | Select-Object -First 3
```

**로그 버킷 정책이 없거나 틀리면 `access_logs` 적용 자체가 `InvalidConfigurationRequest: Access Denied for bucket` 으로 실패한다.**
</details>

## 2. 리스너 기본 403 (CloudFront 미경유 차단)

```hcl
# 파일: set-XX/task-1/terraform/alb.tf
# 기존 aws_lb_listener(HTTP 80) 의 default_action 을 *교체* (in-place)
default_action {
  type = "fixed-response"
  fixed_response {
    content_type = "text/plain"
    message_body = "Forbidden"
    status_code  = "403"
  }
}
```

forward는 `alb-hardening.tf` 의 `aws_lb_listener_rule.addon_origin_verify`(헤더 조건)가 담당한다. POST/GET 분기가 필요하면 규칙을 둘로 나누고 `http_request_method` 조건을 추가한다(set-02 패턴).

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 리스너 | 현재 default_action | 주의 |
| --- | --- | --- | --- |
| set-02 | `aws_lb_listener.book` | 이미 403 fixed-response | 헤더 조건 규칙 2개가 이미 있다 |
| set-03 | Ingress | — | 4번으로 |
| set-07 | `aws_lb_listener.app` | internal ALB + VPC Origin이라 헤더 검증 불필요 | 규칙 10·20 사용 중 |

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "app_listener_arn" { value = aws_lb_listener.book.arn }   # set-07 은 aws_lb_listener.app.arn
```

```powershell
terraform output -raw app_listener_arn
aws elbv2 describe-rules --listener-arn (terraform output -raw app_listener_arn) `
  --query "Rules[].[Priority,Conditions[0].HttpHeaderConfig.HttpHeaderName,Actions[0].Type]" --output table

# 동작 확인 (set-02)
$dns = terraform output -raw book_alb_dns
curl.exe -s -o NUL -w "%{http_code}`n" "http://$dns/"                                    # 403
curl.exe -s -o NUL -w "%{http_code}`n" -H "X-Origin-Verify: <값>" "http://$dns/health"   # 200
```

**set-02는 규칙 개수를 채점한다** (`HttpHeaderConfig.Values[]` 출력 줄 수). 규칙을 추가하면 채점이 깨질 수 있다.

set-07의 앱 ALB는 **internal** 이라 로컬 curl로 못 친다. CloudFront 도메인으로 확인한다:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" "https://$(terraform output -raw cloudfront_domain)/"
```
</details>

## 3. HTTP → HTTPS 리다이렉트 (ACM 있을 때만)

```hcl
# 파일: set-XX/task-1/terraform/alb.tf
# 기존 aws_lb_listener(HTTP 80) 의 default_action 을 *교체*
default_action {
  type = "redirect"
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}
```

HTTPS 리스너 본체는 `alb-hardening.tf` 의 `aws_lb_listener.addon_https` (`addon_albh_certificate_arn` 주입 시 생성).

<details><summary><b>값 뽑기 — 세트별</b></summary>

ACM 인증서는 **ALB와 같은 리전**(ap-northeast-2)에 있어야 한다. CloudFront용 us-east-1 인증서는 ALB에 못 붙인다.

```powershell
aws acm list-certificates --region ap-northeast-2 `
  --query "CertificateSummaryList[].[DomainName,CertificateArn]" --output table
```

**세 세트 모두 ACM 인증서가 없다.** 대회 계정에 도메인이 없으면 이 문항은 사실상 출제되지 않는다 — `addon_albh_certificate_arn = ""` 로 꺼 둔다.
</details>

## 4. set-03 — Ingress 어노테이션으로 같은 것을 한다

set-03의 ALB는 LBC가 만드므로 Terraform 인자가 아니라 **어노테이션**이다. Terraform으로 걸면 LBC 동기화 때 벗겨진다.

```yaml
# 파일: set-03/task-1/k8s/app/05-ingress.yaml   (metadata.annotations 안)
alb.ingress.kubernetes.io/load-balancer-attributes: >-
  access_logs.s3.enabled=true,
  access_logs.s3.bucket=<로그 버킷 이름>,
  access_logs.s3.prefix=alb,
  deletion_protection.enabled=true,
  routing.http.drop_invalid_header_fields.enabled=true
alb.ingress.kubernetes.io/wafv2-acl-arn: "<Web ACL ARN>"
```

<details><summary><b>값 뽑기 — set-03</b></summary>

로그 버킷은 Terraform(이 KIT)이 만들고, 이름만 어노테이션에 넣는다:

```hcl
# 파일: set-03/task-1/terraform/outputs.tf
output "alb_log_bucket" { value = aws_s3_bucket.addon_alb_logs.id }
output "waf_arn"        { value = aws_wafv2_web_acl.wsc2026.arn }
```

```powershell
terraform output -raw alb_log_bucket
terraform output -raw waf_arn

# LBC 가 만든 ALB 주소·ARN
kubectl get ingress -A -o jsonpath='{.items[*].status.loadBalancer.ingress[0].hostname}'
aws elbv2 describe-load-balancers `
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,LoadBalancerArn]" --output table

# 어노테이션 반영 확인 (LBC 로그에 에러가 없어야 한다)
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50
```

로그 버킷 정책의 `aws:SourceArn` 은 LBC가 만든 ALB ARN이라 apply 시점에 모른다 — 정책을 계정 단위(`arn:aws:elasticloadbalancing:ap-northeast-2:<account>:loadbalancer/app/*`)로 넓히거나, ALB 생성 후 2차 apply로 좁힌다.
</details>

## VERIFY

```powershell
$alb = terraform output -raw app_alb_arn
aws elbv2 describe-load-balancer-attributes --load-balancer-arn $alb `
  --query "Attributes[?starts_with(Key,'access_logs') || Key=='deletion_protection.enabled']"
aws elbv2 describe-rules --listener-arn (terraform output -raw app_listener_arn) --output table
aws s3 ls "s3://$(terraform output -raw alb_log_bucket)/alb/AWSLogs/" --recursive | Select-Object -First 3
```

## TROUBLESHOOT

- `access_logs` · `enable_deletion_protection` · `drop_invalid_header_fields` 는 ALB 속성이라 **in-place**. 리스너 `default_action` 교체도 in-place. 규칙 `priority` 변경은 재생성이지만 채점 영향은 없다.
- **로그 버킷 정책이 없거나 틀리면 `access_logs` 적용이 실패한다.** 경로는 `<prefix>/AWSLogs/<account>/*` 정확히. `prefix` 끝에 `/` 를 넣지 않는다.
- principal은 리전에 따라 다르다 — 2022-08 이전 리전은 `data.aws_elb_service_account`, 이후 신규 리전은 `logdelivery.elasticloadbalancing.amazonaws.com`. KIT은 둘 다 넣었다. ap-northeast-2는 구 리전이라 그대로 동작한다.
- 로그 버킷 암호화는 **SSE-S3(AES256)만**. 세트 공통 CMK로 바꾸면 apply는 되지만 로그가 안 쌓인다.
- `enable_deletion_protection = true` 면 `terraform destroy` 가 ALB에서 막힌다. teardown 전에 `false` 로 apply한다.
- 헤더 조건 `values` 는 대소문자 구분 — CloudFront `custom_header` 값과 바이트 단위 동일해야 한다. 값을 바꾸면 배포 갱신(3~5분) 동안 403이 섞인다.
- `http_header_name` 자체는 대소문자 무시지만, 채점이 `describe-rules` 출력 문자열을 비교하면 **과제지 표기대로** 쓴다.
- `drop_invalid_header_fields` 는 채점 curl에 영향이 없다 (유효하지 않은 헤더 이름만 드롭).
- 로그 버킷이 이미 있으면(`BucketAlreadyOwnedByYou`) `addon_albh_log_bucket_prefix` 를 바꾼다.

## 실전 구현 (참고용)

- set-02 task-1 `terraform/alb.tf` — 기본 403 + 헤더 조건 규칙 2개(POST/GET 분기)
- set-07 task-1 `terraform/alb.tf` — internal ALB + CloudFront VPC Origin (헤더 검증 불필요)
- set-03 task-1 `k8s/app/05-ingress.yaml` — LBC 어노테이션 방식
- 액세스 로그 · 삭제 보호 · HTTPS 리스너는 실전 구현이 없다.
