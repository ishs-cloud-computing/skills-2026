# Observability 부착 스니펫

출제지침 예시가 "모니터링 도구 설치" 류라 5개 옵션 중 가장 유력하다.
요구 형태별로 아래 경로 중 하나를 고른다. 전부 기존 구현이 있어 새로 쓰지 않는다.

금지선: 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx) 불가, Helm 은 채점요소 불가.
Prometheus·Grafana·Fluent Bit 는 이 금지 목록에 없다 (set-07 task-1 이 실제로 썼다).
단 채점 대상은 helm 내부 상태가 아니라 결과물(k8s 오브젝트·CloudWatch 지표·대시보드)이어야 한다.

## 경로 A — Container Insights (CloudWatch 계열 요구)

기존 클러스터에 addon 한 줄:

```powershell
eksctl create addon --cluster <클러스터> --region <리전> --name amazon-cloudwatch-observability
```

- 권한: Pod Identity association 포함 선언형이 안전하다 — task-3 `eksctl/cloudwatch-tuned.yaml`
  의 addon 블록(CloudWatchAgentServerPolicy + eks-pod-identity-agent 전제) 을 복사한다.
  eks-pod-identity-agent addon 이 없으면 먼저 설치한다.
- 로그 수집 경로 최적화(특정 namespace 만 수집)도 같은 파일의 fluent-bit extraFiles 패턴 참고.
- 검증: CloudWatch 콘솔 Container Insights 에 클러스터가 뜨고
  `aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/` 에 그룹이 생긴다.

### ECS 클러스터 (set-08/09 task-1 ECS 용)

addon 이 아니라 클러스터 setting 한 블록. in-place 변경(재생성 없음).

```hcl
# aws_ecs_cluster 리소스 안에:
setting {
  name  = "containerInsights"
  value = "enabled" # 과제지가 "enhanced" 를 지정하면 그 값
}
```

- 검증: `aws ecs describe-clusters --clusters <클러스터> --query 'clusters[0].settings'` 에 `enabled`,
  `ECS/ContainerInsights` 네임스페이스에 `RunningTaskCount` 등 메트릭, 로그 그룹 `/aws/ecs/containerinsights/<클러스터>/performance` 생성.
- 켜기 전에 돌던 태스크 메트릭은 소급되지 않는다 — 채점 전 트래픽을 한 번 흘린다.

## 경로 B — Prometheus / Grafana (도구 설치형 요구)

set-07 task-1 `k8s/monitoring/` 을 통째로 복사한다:

- `kube-prometheus-stack-values.yaml` — helm values (클러스터명·스토리지 값만 교체)
- `grafana-targetgroupbinding.yaml` — 기존 ALB 로 Grafana 노출 (TargetGroupBinding)
- `cloudwatch-exporter-values.yaml` — CloudWatch 지표를 Prometheus 로 (IAM 은 irsa/ 스니펫으로)
- `dashboard.json` — Grafana 대시보드 import 용

설치 명령·순서는 set-07 task-1 README 의 monitoring STEP 을 그대로 따른다.

## 경로 C — 로그 수집 (Fluent Bit → CloudWatch Logs)

set-07 task-1 `k8s/logging/fluent-bit.yaml` 복사. 로그 그룹 이름·리전만 교체.
SA 권한은 irsa/ 스니펫(Pod Identity, CloudWatchAgentServerPolicy 수준)으로 준다.

## 경로 D — CloudWatch Alarm / Dashboard / Logs Insights (Terraform)

전부 별도 키트다 — 각 README 의 부착 절차를 따른다. set-07 task-1 `cloudwatch.tf` 는 로그 그룹만 있다(alarm 원본은 set-08 task-1).

| 요구 | 키트 |
| --- | --- |
| 오류 알람·SNS 통지 (로그 메트릭 필터, ALB/RDS/Lambda/WAF/ECS/EKS 메트릭) | `../cw-alarms/` |
| 대시보드 (ALB·RDS·ECS·EKS·Lambda·WAF 위젯, JSON 템플릿) | `../cw-dashboard/` |
| Logs Insights 저장 쿼리 (앱 status/지연, WAF BLOCK 집계) | `../cw-logs-insights/` |

## 경로 E — EKS Control Plane 로깅 ("모든 로그 CloudWatch 전송")

도구 설치가 아니라 클러스터 설정이다. 기존 클러스터엔 한 줄:

```powershell
eksctl utils update-cluster-logging --cluster <클러스터> --region <리전> --enable-types all --approve
```

클러스터 생성 전이면 `cluster.yaml` 에:

```yaml
# ClusterConfig 최상위에:
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]   # 일부만: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    logRetentionInDays: 7 # 과제지 보존 기간. 미지정이면 줄을 지운다(무제한)
```

- 로그 그룹 `/aws/eks/<클러스터>/cluster` 가 생긴다(EKS 가 만든다 — Terraform 으로 선생성하면 CMK 적용 가능, set-07 task-1 `cloudwatch.tf`).
- 검증: `aws eks describe-cluster --name <클러스터> --query 'cluster.logging.clusterLogging[?enabled].types[]'` 에 5종.
- 기존 클러스터에 Terraform 이 만든 `/aws/eks/<클러스터>/cluster` 로그 그룹이 이미 있으면 그대로 거기에 쌓인다(충돌 없음).

## 경로 F — Fargate Pod 로그 → CloudWatch (EKS Fargate)

Fargate 에는 DaemonSet(Fluent Bit·Container Insights agent)이 못 뜬다. 내장 로그 라우터를 `aws-observability` 네임스페이스 + `aws-logging` ConfigMap 으로 켠다 — 이름 둘 다 고정(EKS 가 이 이름만 읽는다).

1. `fargate-logging.yaml` 의 `region`·`log_group_name` 을 고치고 적용:

   ```powershell
   kubectl apply -f fargate-logging.yaml
   ```

2. pod execution role 에 로그 쓰기 정책 (없으면 파드는 뜨지만 로그가 안 간다):

   ```powershell
   $role = (aws eks describe-fargate-profile --cluster-name <클러스터> --fargate-profile-name <프로필> --query fargateProfile.podExecutionRoleArn --output text).Split('/')[-1]
   aws iam put-role-policy --role-name $role --policy-name fargate-cloudwatch-logs --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogStream","logs:CreateLogGroup","logs:DescribeLogStreams","logs:PutLogEvents"],"Resource":"*"}]}'
   ```

3. **이미 떠 있는 Fargate 파드에는 소급되지 않는다** — `kubectl rollout restart deploy/<앱>` 으로 재기동.
4. 검증: `kubectl describe pod <파드>` 의 Annotations 또는 Events 에 `LoggingEnabled`, `aws logs describe-log-groups --log-group-name-prefix <log_group_name>`.

set-08 task-2 module-4(Fargate profile keda·karpenter) 처럼 컨트롤러만 Fargate 인 구성은 워커(EC2) 로그가 아니라 Fargate 파드 로그만 이 경로로 간다 — 워커는 경로 A/C.

## 함정

- Control Plane 로깅 요구는 경로 E — addon 설치로 착각하지 않는다.
- Container Insights 로그 그룹 retention 기본은 무제한 — 과제지가 보존 기간을 지정하면
  `aws logs put-retention-policy` 로 맞춘다.
- Grafana 노출은 새 ALB 를 만들지 말고 기존 ALB + TargetGroupBinding 재사용
  (불필요 리소스 감점, set-07 패턴).
