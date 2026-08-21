# cw-dashboard 부착 스니펫

CloudWatch 대시보드 한 장 — ALB·RDS·ECS·EKS(Container Insights)·Lambda·WAF 위젯을 변수로 골라 넣는다.
task-3 "모니터링 환경" 요구, set-08/09 task-1 ECS 대시보드 추가 문항, 1과제 Observability 옵션(대시보드 형)에 대응한다.

## 파일

- `cw-dashboard.tf` — `aws_cloudwatch_dashboard` 1개. `templatefile` 로 JSON 렌더
- `dashboard.json.tftpl` — 위젯 JSON. dimension 변수가 빈 위젯은 `%{ if }` 로 빠진다. 제목 텍스트 위젯은 항상 들어간다
- `variables.tf` — `addon_cwdash_*` 변수. 이름·리전·dimension 전부 변수

## 부착 절차

1. 세 파일을 `set-XX/task-Y/terraform/` 으로 복사한다. `dashboard.json.tftpl` 은 `.tf` 와 **같은 디렉토리**에 둔다(`path.module` 기준).
2. `terraform.tfvars` 에 값을 넣는다. 빈 문자열인 위젯은 생성되지 않는다. 기존 리소스를 직접 참조하려면 `cw-dashboard.tf` 의 `var.addon_cwdash_alb_arn_suffix` 를 `aws_lb.<기존>.arn_suffix` 로, `var.addon_cwdash_rds_instance_id` 를 `aws_db_instance.<기존>.identifier` 로 바꾼다.

   ```hcl
   addon_cwdash_name                 = "skills-dashboard"   # 과제지 명시 이름
   addon_cwdash_region               = "ap-northeast-2"
   addon_cwdash_alb_arn_suffix       = "app/skills-alb/0123456789abcdef"
   addon_cwdash_rds_instance_id      = "skills-db"
   addon_cwdash_ecs_cluster_name     = "skills-cluster"
   addon_cwdash_ecs_service_name     = "skills-service"
   addon_cwdash_eks_cluster_name     = "skills-eks"        # Container Insights addon 설치돼 있을 때만
   addon_cwdash_lambda_function_name = "skills-func"
   addon_cwdash_waf_acl_name         = "skills-waf"
   addon_cwdash_waf_metric_region    = "us-east-1"         # REGIONAL 이면 ALB 리전
   addon_cwdash_waf_dimension_region = "Global"            # REGIONAL 이면 "ap-northeast-2"
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
4. 검증:

   ```powershell
   aws cloudwatch get-dashboard --dashboard-name skills-dashboard --query DashboardBody --output text | ConvertFrom-Json | Select-Object -ExpandProperty widgets | Select-Object type, @{n='title';e={$_.properties.title}}
   ```

   콘솔 CloudWatch → Dashboards 에서 위젯에 데이터가 그려지는지 본다(메트릭 없음 = dimension 오타).

## 블록

Terraform 없이 CLI 로 넣을 때(콘솔 JSON 편집 → 파일 저장 후):

```powershell
aws cloudwatch put-dashboard --dashboard-name skills-dashboard --dashboard-body file://dashboard.json
```

`dashboard.json.tftpl` 을 손으로 렌더해 쓰려면 `${...}` 자리를 값으로 채우고 `%{ if }`·`%{ endif }` 줄을 지운다.

위젯 한 개 추가(템플릿 안 `]` 앞에, 바로 앞 위젯 뒤에 `,` 로 이어서):

```json
{
  "type": "metric", "width": 12, "height": 6,
  "properties": {
    "title": "<제목>", "region": "${region}", "view": "timeSeries", "stat": "Sum", "period": ${period},
    "metrics": [["<Namespace>", "<MetricName>", "<DimName>", "<DimValue>"]]
  }
}
```

## 함정

- 대시보드 본문 변경은 in-place. `dashboard_name` 변경은 ⚠ 재생성(이름이 식별자) — 채점 영향 없음.
- 위젯 `x`·`y` 를 일부러 뺐다 — 넣으면 전 위젯에 넣어야 하고, 빈 위젯이 빠질 때 좌표가 겹친다. 자동 배치(순서대로 채움)로 둔다.
- ALB `LoadBalancer` dimension 은 ARN 이 아니라 `app/<이름>/<id>` (`arn_suffix`). 이름만 넣으면 데이터가 안 뜬다.
- WAF CLOUDFRONT scope 는 메트릭 리전 `us-east-1` + dimension `Region=Global`. REGIONAL 은 둘 다 ALB 리전. 대시보드 리소스 자체는 리전 무관이라 provider alias 가 필요 없다.
- `ContainerInsights`(EKS) / `ECS/ContainerInsights` 네임스페이스는 addon(EKS) 또는 `containerInsights` setting(ECS) 이 켜져야 생긴다 — observability/ 키트 참고. 안 켜면 위젯이 비어 있을 뿐 apply 는 성공한다.
- `templatefile` 은 `.tftpl` 안에서 `$${`·`%%{` 로 이스케이프해야 리터럴 `${` 를 쓸 수 있다. CloudWatch Math 표현식(`"expression": "..."`) 은 `$`을 안 쓰므로 무관.
- 채점 스크립트가 위젯 개수·제목을 읽을 수 있다(task-3 "모니터링 환경" 류). 과제지가 지정한 메트릭이 있으면 위젯 제목을 그 문구로 맞춘다.

## 실전 구현 (참고용)

없음 — 저장소 task-1 세트에 `aws_cloudwatch_dashboard` 는 없다. Grafana 대시보드는 set-03/07 task-1 `k8s/monitoring/dashboard.json`(CloudWatch 와 무관).
