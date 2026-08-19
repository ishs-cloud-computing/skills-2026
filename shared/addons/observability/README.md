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

## 경로 D — CloudWatch Alarm / Dashboard (Terraform)

set-07 task-1 `terraform/cloudwatch.tf` 의 alarm·dashboard 패턴을 복사한다.
대시보드는 콘솔에서 만들면 재현이 안 된다 — JSON 을 소스로 두고
`aws cloudwatch put-dashboard --dashboard-name <이름> --dashboard-body file://dashboard.json`
또는 `aws_cloudwatch_dashboard` 리소스로 넣는다. 이름은 과제지 명시값 정확 일치.

## 함정

- Control Plane 로깅("모든 로그 CloudWatch 전송") 요구면 도구 설치가 아니라 클러스터 설정이다:
  기존 클러스터엔 `eksctl utils update-cluster-logging --cluster <클러스터> --region <리전> --enable-types all --approve`.
- Container Insights 로그 그룹 retention 기본은 무제한 — 과제지가 보존 기간을 지정하면
  `aws logs put-retention-policy` 로 맞춘다.
- Grafana 노출은 새 ALB 를 만들지 말고 기존 ALB + TargetGroupBinding 재사용
  (불필요 리소스 감점, set-07 패턴).
