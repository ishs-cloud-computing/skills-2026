# Observability 부착 KIT

1과제 추가 문항 5개 중 **가장 유력**하다 (출제지침 예시가 "모니터링 도구 설치" 류). 요구 형태별로 아래 경로 중 하나를 고른다. 전부 기존 구현이 있어 새로 쓰지 않는다.

## 이 KIT이 맞나 — 경로 판정

| 과제지 문장 | 경로 |
| --- | --- |
| "Container Insights" · "CloudWatch로 컨테이너 지표" | **A** — addon 한 줄 |
| "Prometheus" · "Grafana" · "모니터링 도구를 설치" | **B** — set-07 `k8s/monitoring/` 복사 |
| "Pod 로그를 CloudWatch로" · "로그 수집" | **C** — Fluent Bit |
| "경보" · "대시보드" · "로그 쿼리" | **D** — 별도 KIT 3개 |
| "클러스터의 모든 로그를 CloudWatch로 전송" | **E** — Control Plane 로깅 (addon 아님) |
| Fargate에서 로그 수집 | **F** — 내장 로그 라우터 |

금지선: 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx) 불가, Helm은 채점요소가 될 수 없다. **Prometheus·Grafana·Fluent Bit는 금지 목록에 없다** (set-07 task-1이 실제로 썼다). 단 채점 대상은 helm 내부 상태가 아니라 결과물(k8s 오브젝트·CloudWatch 지표·대시보드)이어야 한다.

## 세트별 현재 관측성 구성

| 세트 | 클러스터 | 로그 수집 매니페스트 | Prometheus/Grafana | Grafana 노출 |
| --- | --- | --- | --- | --- |
| set-02 | `wskorea26-cluster` | `k8s/monitoring/fluent-bit.yaml` (ns `monitoring`) | `kube-prometheus-stack-values.yaml` | TargetGroupBinding (`aws_lb.grafana`) |
| set-03 | `wsc2026-eks-cluster` | `k8s/logging/fluent-bit.yaml` (ns `observability`) | + `prometheus-rules.yaml` | k8s Ingress (LBC) |
| set-07 | `unicorn-eks-cluster` | `k8s/logging/fluent-bit.yaml` (ns `logging`) | + `cloudwatch-exporter-values.yaml` | TargetGroupBinding (`aws_lb.grafana`) |

리전은 세 세트 모두 `ap-northeast-2`.

## CHANGE — 당일 고치는 값

Terraform 변수 없음. 아래 스니펫의 클러스터명·로그 그룹명·리전을 세트 값으로 바꾼다.

## CHECK · RUN

```powershell
kubectl config current-context   # 채점 대상 클러스터가 맞는지
kubectl apply -f <복사한 파일>
kubectl get pods -A
```

## 경로 A — Container Insights (EKS)

```powershell
eksctl create addon --cluster <클러스터> --region ap-northeast-2 --name amazon-cloudwatch-observability
```

권한은 Pod Identity association 포함 선언형이 안전하다 — task-3 `eksctl/cloudwatch-tuned.yaml` 의 addon 블록(CloudWatchAgentServerPolicy + `eks-pod-identity-agent` 전제)을 복사한다.

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
# set-02
eksctl create addon --cluster wskorea26-cluster    --region ap-northeast-2 --name amazon-cloudwatch-observability
# set-03
eksctl create addon --cluster wsc2026-eks-cluster  --region ap-northeast-2 --name amazon-cloudwatch-observability
# set-07
eksctl create addon --cluster unicorn-eks-cluster  --region ap-northeast-2 --name amazon-cloudwatch-observability
```

클러스터 이름을 output에서 뽑으려면:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "cluster_name" { value = var.cluster_name }
```

set-03·set-07은 `cluster_arn` output이 이미 있어 잘라 써도 된다 (set-02는 `cluster_arn` 도 없다):

```powershell
(terraform output -raw cluster_arn).Split('/')[-1]

aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/ --query "logGroups[].logGroupName"
aws cloudwatch list-metrics --namespace ContainerInsights --query "Metrics[0:5].MetricName"
```
</details>

<details><summary><b>ECS Container Insights — task-1에는 ECS가 없다 (2과제/task-3용)</b></summary>

addon이 아니라 클러스터 setting 한 블록이다. in-place 변경(재생성 없음).

```hcl
# 파일: <ECS 가 있는 디렉터리>/ecs.tf
# 기존 aws_ecs_cluster 리소스 블록 *안에* 추가
setting {
  name  = "containerInsights"
  value = "enabled"   # 과제지가 "enhanced" 를 지정하면 그 값
}
```

```powershell
aws ecs describe-clusters --clusters <클러스터> --query "clusters[0].settings"
```

켜기 전에 돌던 태스크 메트릭은 **소급되지 않는다** — 채점 전 트래픽을 한 번 흘린다. 로그 그룹은 `/aws/ecs/containerinsights/<클러스터>/performance`.
</details>

## 경로 B — Prometheus / Grafana (도구 설치형)

**set-07 task-1 `k8s/monitoring/` 을 통째로 복사한다.**

| 파일 | 무엇 | 고칠 값 |
| --- | --- | --- |
| `kube-prometheus-stack-values.yaml` | helm values | 클러스터명·스토리지·admin 계정 |
| `grafana-targetgroupbinding.yaml` | 기존 ALB로 Grafana 노출 | 타깃그룹 ARN |
| `cloudwatch-exporter-values.yaml` | CloudWatch 지표 → Prometheus | 리전·IAM(→ [irsa](../irsa/README.md)) |
| `dashboard.json` | Grafana 대시보드 import | 데이터소스 uid |

설치 명령·순서는 set-07 task-1 README의 monitoring STEP을 그대로 따른다.

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | Grafana 타깃그룹 output | Grafana 주소 output | admin 계정 output |
| --- | --- | --- | --- |
| set-02 | `grafana_target_group_arn` (있음) | `grafana_alb_dns` (있음) | `grafana_admin_user` · `grafana_admin_password` (있음) |
| set-03 | **없음** — LBC Ingress가 ALB를 만든다 | **없음** | **없음** |
| set-07 | `grafana_target_group_arn` (있음) | `grafana_alb_dns_name` (있음) | **없음** |

```powershell
# set-02
terraform output -raw grafana_target_group_arn
"http://$(terraform output -raw grafana_alb_dns)"
terraform output -raw grafana_admin_user
terraform output -raw grafana_admin_password      # sensitive

# set-07
terraform output -raw grafana_target_group_arn
"http://$(terraform output -raw grafana_alb_dns_name)"

# set-03 — Ingress 가 만든 주소
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
```

set-03·set-07에 admin 계정 output이 필요하면:

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "grafana_admin_password" {
  value     = var.grafana_admin_password
  sensitive = true
}
```
</details>

## 경로 C — 로그 수집 (Fluent Bit → CloudWatch Logs)

set-07 task-1 `k8s/logging/fluent-bit.yaml` 복사. **로그 그룹 이름·리전만** 교체한다. SA 권한은 [irsa](../irsa/README.md) 로 준다 (CloudWatchAgentServerPolicy 수준).

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 매니페스트 | SA / ns | 로그 그룹 리소스 | output |
| --- | --- | --- | --- | --- |
| set-02 | `k8s/monitoring/fluent-bit.yaml` | `fluent-bit` / `monitoring` | `aws_cloudwatch_log_group.pod_logs` | **없음** |
| set-03 | `k8s/logging/fluent-bit.yaml` | `fluent-bit` / `observability` | `aws_cloudwatch_log_group.book_app` | `app_log_group` (있음) |
| set-07 | `k8s/logging/fluent-bit.yaml` | `fluent-bit` / `logging` | `aws_cloudwatch_log_group.book_app` | **없음** |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.pod_logs.name }

# 파일: set-07/task-1/terraform/outputs.tf
output "app_log_group" { value = aws_cloudwatch_log_group.book_app.name }
```

```powershell
$lg = terraform output -raw app_log_group
aws logs tail $lg --since 5m --follow
kubectl -n <fluent-bit ns> logs ds/fluent-bit --tail=50
```
</details>

## 경로 D — CloudWatch Alarm / Dashboard / Logs Insights (Terraform)

| 요구 | KIT |
| --- | --- |
| 오류 알람·SNS 통지 (로그 메트릭 필터, ALB/Lambda/WAF/EKS 메트릭) | [cw-alarms](../cw-alarms/README.md) |
| 대시보드 (ALB·EKS·Lambda·WAF 위젯) | [cw-dashboard](../cw-dashboard/README.md) |
| Logs Insights 저장 쿼리 (앱 status/지연, WAF BLOCK 집계) | [cw-logs-insights](../cw-logs-insights/README.md) |

## 경로 E — EKS Control Plane 로깅

**도구 설치가 아니라 클러스터 설정이다.** 기존 클러스터엔 한 줄:

```powershell
eksctl utils update-cluster-logging --cluster <클러스터> --region ap-northeast-2 --enable-types all --approve
```

클러스터 생성 전이면:

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml   (ClusterConfig 최상위)
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]      # 일부만: ["api","audit","authenticator","controllerManager","scheduler"]
    logRetentionInDays: 7   # 과제지 보존 기간. 미지정이면 줄을 지운다(무제한)
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | Control Plane 로그 그룹 | Terraform 선생성 |
| --- | --- | --- |
| set-02 | `/aws/eks/wskorea26-cluster/cluster` | **없음** — EKS가 만든다 |
| set-03 | `/aws/eks/wsc2026-eks-cluster/cluster` | **없음** |
| set-07 | `aws_cloudwatch_log_group.eks_cluster` | **있음** (CMK 적용 목적) |

```hcl
# 파일: set-07/task-1/terraform/outputs.tf
output "eks_cluster_log_group" { value = aws_cloudwatch_log_group.eks_cluster.name }
```

```powershell
eksctl utils update-cluster-logging --cluster wskorea26-cluster   --region ap-northeast-2 --enable-types all --approve
eksctl utils update-cluster-logging --cluster wsc2026-eks-cluster --region ap-northeast-2 --enable-types all --approve
eksctl utils update-cluster-logging --cluster unicorn-eks-cluster --region ap-northeast-2 --enable-types all --approve

aws eks describe-cluster --name <클러스터> --region ap-northeast-2 `
  --query "cluster.logging.clusterLogging[?enabled].types[]"
```

Terraform이 만든 `/aws/eks/<클러스터>/cluster` 로그 그룹이 이미 있으면 **그대로 거기에 쌓인다** (충돌 없음).
</details>

<details><summary><b>경로 F — Fargate Pod 로그 (task-1 세 세트는 전부 관리형 노드그룹이라 해당 없음)</b></summary>

Fargate에는 DaemonSet(Fluent Bit·Container Insights agent)이 못 뜬다. 내장 로그 라우터를 `aws-observability` 네임스페이스 + `aws-logging` ConfigMap으로 켠다 — **이름 둘 다 고정**(EKS가 이 이름만 읽는다).

```powershell
# 1) fargate-logging.yaml 의 region·log_group_name 을 고치고
kubectl apply -f fargate-logging.yaml

# 2) pod execution role 에 로그 쓰기 정책 (없으면 파드는 뜨지만 로그가 안 간다)
$role = (aws eks describe-fargate-profile --cluster-name <클러스터> --fargate-profile-name <프로필> `
  --query fargateProfile.podExecutionRoleArn --output text).Split('/')[-1]
aws iam put-role-policy --role-name $role --policy-name fargate-cloudwatch-logs `
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogStream","logs:CreateLogGroup","logs:DescribeLogStreams","logs:PutLogEvents"],"Resource":"*"}]}'

# 3) 이미 떠 있는 파드에는 소급되지 않는다
kubectl rollout restart deploy/<앱>
```
</details>

## VERIFY

```powershell
kubectl get pods -n <monitoring ns>
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/
aws logs tail (terraform output -raw app_log_group) --since 5m
```

## TROUBLESHOOT

- **Control Plane 로깅 요구를 addon 설치로 착각하지 않는다** — 경로 E다.
- Container Insights 로그 그룹 retention 기본은 **무제한**. 과제지가 보존 기간을 지정하면 `aws logs put-retention-policy` 로 맞춘다.
- Grafana 노출에 **새 ALB를 만들지 않는다.** 기존 ALB + TargetGroupBinding 재사용 (불필요 리소스 감점, set-07 패턴). set-03은 Ingress에 path 룰을 추가한다.
- helm 설치 상태 자체는 채점 대상이 될 수 없다. 결과물(k8s 오브젝트·지표·대시보드)이 보이는지로 확인한다.
