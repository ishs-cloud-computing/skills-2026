# alb-hardening 부착 스니펫

기존 ALB 에 액세스 로그·삭제 보호·헤더 검증 리스너 규칙·HTTPS 리스너를 붙이는 키트.
1과제 Security/Observability 옵션 확장(set-08/09 task-1), set-02 m2 ALB 에 대응한다.

## 파일

- `alb-hardening.tf` — 로그 버킷(SSE-S3) + 버킷 정책(ELB 계정 + logdelivery 서비스 principal) · 헤더 조건 리스너 규칙(`count`, 리스너 ARN 있을 때만) · HTTPS 리스너(`count`, ACM ARN 있을 때만)
- `variables.tf` — `addon_albh_*` 변수. 기존 리소스(리스너·타깃 그룹·ALB ARN)는 변수로 받는다

`access_logs`·`enable_deletion_protection`·`drop_invalid_header_fields` 는 기존 `aws_lb` 안에 넣는 인자라 README 블록.

## 부착 절차

1. `alb-hardening.tf`·`variables.tf` 를 `set-XX/task-Y/terraform/` 으로 복사한다. 로그만 필요하면 리스너 규칙·HTTPS 리소스 블록은 지워도 된다(변수 기본값이 "" 라 count 0 으로도 안 생긴다).
2. 기존 `aws_lb` 리소스 안에 필요한 블록(아래)을 넣는다. `access_logs` 는 로그 버킷 정책 뒤에 적용돼야 하므로 `aws_lb` 에 `depends_on = [aws_s3_bucket_policy.addon_alb_logs]` 추가.
3. `terraform.tfvars`. 기존 리소스를 직접 참조하려면 `var.addon_albh_listener_arn` 을 `aws_lb_listener.<기존>.arn` 으로 바꾼다.

   ```hcl
   addon_albh_log_bucket_prefix = "skills-alb-logs"      # 과제지 명시 이름
   addon_albh_log_prefix        = "alb"
   addon_albh_listener_arn      = "arn:aws:elasticloadbalancing:ap-northeast-2:<ACCOUNT>:listener/app/skills-alb/<id>/<id>"
   addon_albh_target_group_arn  = "arn:aws:elasticloadbalancing:ap-northeast-2:<ACCOUNT>:targetgroup/skills-tg/<id>"
   addon_albh_rule_priority     = 1
   addon_albh_header_name       = "X-Origin-Verify"
   addon_albh_header_value      = "<CloudFront custom_header 와 같은 값>"
   addon_albh_alb_arn           = ""                    # HTTPS 리스너 쓸 때만
   addon_albh_certificate_arn   = ""                    # ACM ARN (같은 리전)
   ```

4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 `aws_lb` 가 **update in-place** 인지 확인 → `terraform apply`.
5. 검증:

   ```powershell
   aws elbv2 describe-load-balancer-attributes --load-balancer-arn <ALB ARN> --query "Attributes[?starts_with(Key,'access_logs') || Key=='deletion_protection.enabled' || Key=='routing.http.drop_invalid_header_fields.enabled']"
   aws elbv2 describe-rules --listener-arn <리스너 ARN> --query 'Rules[].[Priority,Conditions[0].HttpHeaderConfig.HttpHeaderName,Actions[0].Type]' --output table
   curl.exe -s -o NUL -w "%{http_code}`n" http://<ALB DNS>/                                   # 403
   curl.exe -s -o NUL -w "%{http_code}`n" -H "X-Origin-Verify: <값>" http://<ALB DNS>/health  # 200
   aws s3 ls s3://skills-alb-logs-<ACCOUNT>/alb/AWSLogs/ --recursive | Select-Object -First 3   # 5분 주기 기록, 첫 파일 ELBAccessLogTestFile
   ```

## 블록

### 액세스 로그 · 삭제 보호 · 잘못된 헤더 드롭

```hcl
# aws_lb 리소스 안에:
access_logs {
  bucket  = aws_s3_bucket.addon_alb_logs.id
  prefix  = var.addon_albh_log_prefix
  enabled = true
}

enable_deletion_protection = true
drop_invalid_header_fields = true
```

### 리스너 기본 403 (CloudFront 미경유 차단)

```hcl
# 기존 aws_lb_listener(HTTP 80) 의 default_action 을 교체:
default_action {
  type = "fixed-response"
  fixed_response {
    content_type = "text/plain"
    message_body = "Forbidden"
    status_code  = "403"
  }
}
```

forward 는 `alb-hardening.tf` 의 `aws_lb_listener_rule.addon_origin_verify`(헤더 조건)가 담당한다.
POST/GET 분기가 필요하면 규칙을 둘로 나누고 `http_request_method` 조건을 추가한다(set-02 task-1 `alb.tf`).

### HTTP → HTTPS 리다이렉트 (ACM 있을 때)

```hcl
# 기존 aws_lb_listener(HTTP 80) 의 default_action 을 교체:
default_action {
  type = "redirect"
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}
```

HTTPS 리스너 본체는 `alb-hardening.tf` 의 `aws_lb_listener.addon_https`(`addon_albh_certificate_arn` 주입 시 생성).

## 함정

- `access_logs`·`enable_deletion_protection`·`drop_invalid_header_fields` 는 ALB 속성이라 **in-place**. 리스너 `default_action` 교체도 in-place. 규칙 `priority` 변경은 ⚠ 재생성(채점 영향 없음).
- **로그 버킷 정책이 없거나 틀리면 `access_logs` 적용 자체가 `InvalidConfigurationRequest: Access Denied for bucket` 로 실패한다.** 경로는 `<prefix>/AWSLogs/<account>/*` 정확히. `prefix` 끝에 `/` 를 넣지 않는다(ALB 가 붙인다).
- principal 은 리전에 따라 다르다 — 2022-08 이전 리전은 `data.aws_elb_service_account`(ELB 계정 ID), 이후 신규 리전은 `logdelivery.elasticloadbalancing.amazonaws.com`. 스니펫은 둘 다 넣었다. 신규 리전(ap-southeast-3·4 등)에서는 data source 가 에러 → data 블록과 첫 statement 를 지운다. provider 6.x 에서 data source 유지 확인(v6.31 문서).
- 로그 버킷 암호화는 **SSE-S3(AES256)만**. 세트 공통 CMK 로 바꾸면 apply 는 되지만 로그가 안 쌓인다.
- `enable_deletion_protection = true` 면 `terraform destroy` 가 ALB 에서 막힌다. teardown 전에 `false` 로 apply 하거나 콘솔에서 끈다. 런북 teardown 절에 한 줄 추가.
- `drop_invalid_header_fields` 는 채점 curl 에 영향 없음(유효하지 않은 헤더 이름만 드롭).
- 헤더 조건 `values` 는 대소문자 구분. CloudFront `custom_header` 값과 **바이트 단위 동일**해야 한다. 값을 바꾸면 배포 갱신(3~5분) 동안 403 이 섞인다.
- `http_header_name` 은 대소문자 무시(`X-Origin-Verify` == `x-origin-verify`), 채점 스크립트가 describe-rules 출력 문자열을 비교하면 과제지 표기대로 쓴다.
- set-02 mark 7-2 는 `HttpHeaderConfig.Values[]` 출력 줄 수를 센다 — 규칙 개수를 과제지대로 유지(추가 규칙이 채점을 깨뜨릴 수 있음).
- HTTPS 리스너는 ACM 인증서가 **같은 리전**에 있어야 한다(CloudFront 용 us-east-1 인증서는 ALB 에 못 붙인다). 대회 계정에 도메인이 없으면 HTTPS 리스너 문항은 사실상 출제되지 않는다 — 변수 기본값 "" 로 꺼 둔다.
- 로그 버킷이 이미 있으면(`BucketAlreadyOwnedByYou`) `addon_albh_log_bucket_prefix` 를 바꾼다. 기존 버킷 삭제 시도 금지.

## 실전 구현 (참고용)

- set-02 task-1 `terraform/alb.tf` — 기본 403 + 헤더 조건 규칙 2개(POST/GET 분기)
- set-08 task-1 `terraform/alb.tf`·`cloudfront.tf` — `random_password` 헤더 값 + 단일 헤더 규칙
- set-07 task-1 `terraform/alb.tf` — internal ALB + VPC Origin(헤더 검증 불필요)
- 액세스 로그·삭제 보호·HTTPS 리스너 실전 구현은 없음
