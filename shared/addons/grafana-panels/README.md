# Grafana 패널·알림 자산 KIT

이미 서 있는 `k8s/monitoring/` 스택에 **패널·알림 규칙만** 얹는 자산 묶음. 독립 Helm release나 독립 apply 대상이 아니다.

## 이 KIT이 맞나

- 과제지가 **"대시보드에 패널 추가"·"Prometheus 알림 규칙"·"Grafana를 ALB로 노출"** → 맞다.
- **스택 자체를 새로 세운다** → [observability](../observability/README.md) 경로 B를 먼저 한다.
- **CloudWatch 대시보드** 요구 → [cw-dashboard](../cw-dashboard/README.md).

## 세트별 현재 monitoring 구성

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 클러스터 | `wskorea26-cluster` | `wsc2026-eks-cluster` | `unicorn-eks-cluster` |
| monitoring 파일 | `k8s/monitoring/` : `kube-prometheus-stack-values.yaml` · `dashboard.json` · `grafana-targetgroupbinding.yaml` · `fluent-bit.yaml` | `k8s/monitoring/` : `kube-prometheus-stack-values.yaml` · `dashboard.json` · **`prometheus-rules.yaml`** | `k8s/monitoring/` : `kube-prometheus-stack-values.yaml` · `dashboard.json` · `grafana-targetgroupbinding.yaml` · **`cloudwatch-exporter-values.yaml`** |
| Grafana 노출 | TargetGroupBinding → `aws_lb.grafana` | **k8s Ingress**(LBC) | TargetGroupBinding → `aws_lb.grafana` |
| PrometheusRule | **없음** | **있음** (복사 원본) | **없음** |
| Grafana 관리자 output | `grafana_admin_user` · `grafana_admin_password` | 없음 | 없음 |

## 포함 파일

| 파일 | 어디에 병합 |
| --- | --- |
| `kube-prometheus-stack-values.yaml` | 기존 values에 **섹션만** 병합 (전체 대체 아님) |
| `dashboard-panels.json` | 기존 `dashboard.json` 의 `panels[]` 에 병합 |
| `grafana-alerting-provisioning.yaml` | Grafana unified alerting ConfigMap |
| `grafana-targetgroupbinding.yaml` | 기존 ALB Target Group 재사용 (**새 ALB를 만들지 않는다**) |
| `prometheus-rules.yaml` | PrometheusRule 알림 규칙 |

## CHANGE — 당일 고치는 값

Terraform 변수 없음. 아래를 대상 세트 값으로 바꾼다: **클러스터명 · namespace · StorageClass · Target Group ARN · 데이터소스 URL · 대시보드 이름**.

## CHECK · RUN

```powershell
kubectl config current-context   # 채점 대상 클러스터가 맞는지
kubectl get pods -n <monitoring ns>
```

## 1. Grafana 노출 — TargetGroupBinding

```yaml
# 파일: set-XX/task-1/k8s/monitoring/grafana-targetgroupbinding.yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: grafana-tgb
  namespace: monitoring          # ← 세트별 ns
spec:
  serviceRef:
    name: monitoring-grafana     # helm release 이름에 따라 달라진다
    port: 80
  targetGroupARN: "${GRAFANA_TARGET_GROUP_ARN}"
  targetType: ip
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 타깃그룹 output | Grafana 주소 output | 노출 방식 |
| --- | --- | --- | --- |
| set-02 | `grafana_target_group_arn` (있음) | `grafana_alb_dns` (있음) | TargetGroupBinding |
| set-03 | **없음** | **없음** | **Ingress** — 아래 2번 |
| set-07 | `grafana_target_group_arn` (있음) | `grafana_alb_dns_name` (있음) | TargetGroupBinding |

```powershell
# set-02
$env:GRAFANA_TARGET_GROUP_ARN = terraform output -raw grafana_target_group_arn
"http://$(terraform output -raw grafana_alb_dns)"

# set-07
$env:GRAFANA_TARGET_GROUP_ARN = terraform output -raw grafana_target_group_arn
"http://$(terraform output -raw grafana_alb_dns_name)"

kubectl apply -f k8s/monitoring/grafana-targetgroupbinding.yaml
kubectl get targetgroupbinding -A
# 타깃이 healthy 로 붙었는지
aws elbv2 describe-target-health --target-group-arn $env:GRAFANA_TARGET_GROUP_ARN `
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
```

**새 ALB·Target Group을 추가 생성하지 않는다** — 불필요 리소스 감점 대상이다.
</details>

## 2. set-03 — Ingress에 Grafana 경로 추가

```yaml
# 파일: set-03/task-1/k8s/app/05-ingress.yaml   (spec.rules[].http.paths 에 추가)
- path: /grafana
  pathType: Prefix
  backend:
    service:
      name: monitoring-grafana
      port:
        number: 80
```

<details><summary><b>값 뽑기 — set-03</b></summary>

Grafana를 서브패스로 노출하면 values의 `grafana.grafana.ini.server` 도 같이 고쳐야 링크가 깨지지 않는다:

```yaml
# 파일: set-03/task-1/k8s/monitoring/kube-prometheus-stack-values.yaml
grafana:
  grafana.ini:
    server:
      root_url: "http://<ALB DNS>/grafana"
      serve_from_sub_path: true
```

```powershell
# LBC 가 만든 ALB 주소 — root_url 에 넣을 값
kubectl get ingress -A -o jsonpath='{.items[*].status.loadBalancer.ingress[0].hostname}'

kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=30
curl.exe -s -o NUL -w "%{http_code}`n" "http://<ALB DNS>/grafana/login"
```
</details>

## 3. PrometheusRule (알림 규칙)

```yaml
# 파일: set-XX/task-1/k8s/monitoring/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-rules
  namespace: monitoring          # ← 세트별 ns
  labels:
    release: monitoring          # kube-prometheus-stack 이 이 label 로 룰을 주워간다
spec:
  groups:
    - name: app
      rules:
        - alert: HighErrorRate
          expr: sum(rate(http_requests_total{status=~"5.."}[5m])) > 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "5xx rate high"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**`labels.release` 값이 helm release 이름과 다르면 Prometheus가 룰을 안 주워간다.** 먼저 확인:

```powershell
helm list -A
kubectl get prometheus -A -o jsonpath='{.items[0].spec.ruleSelector}'

kubectl apply -f k8s/monitoring/prometheus-rules.yaml
kubectl get prometheusrule -A

# Prometheus 가 실제로 로드했는지 (포트포워딩)
kubectl -n <monitoring ns> port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
# 다른 창에서
curl.exe -s http://localhost:9090/api/v1/rules | ConvertFrom-Json |
  Select-Object -ExpandProperty data | Select-Object -ExpandProperty groups |
  Select-Object name, @{n='rules';e={$_.rules.name -join ','}}
```

| 세트 | PrometheusRule |
| --- | --- |
| set-02 | 없음 — 이 파일을 새로 넣는다 |
| set-03 | **`k8s/monitoring/prometheus-rules.yaml` 이 이미 있다** — 복사 원본으로 쓴다 |
| set-07 | 없음 |
</details>

## 4. 대시보드 패널 추가

```json
// 파일: set-XX/task-1/k8s/monitoring/dashboard.json   (panels[] 배열 안)
{
  "type": "timeseries",
  "title": "<과제지 지정 제목>",
  "datasource": { "type": "prometheus", "uid": "<데이터소스 uid>" },
  "targets": [
    { "expr": "sum(rate(http_requests_total[5m])) by (status)", "legendFormat": "{{status}}" }
  ],
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 }
}
```

<details><summary><b>값 뽑기 — 세트별 (datasource uid를 틀리면 No Data가 뜬다)</b></summary>

세 세트 모두 `k8s/monitoring/dashboard.json` 이 이미 있다. **패널을 새로 만들기보다 그 파일의 기존 패널을 복사해 expr만 바꾸는 쪽이 빠르다.**

```powershell
# 현재 대시보드의 datasource uid 목록
Get-Content k8s/monitoring/dashboard.json | ConvertFrom-Json |
  Select-Object -ExpandProperty panels |
  Select-Object title, @{n='ds';e={$_.datasource.uid}}

# 클러스터에 실제로 있는 데이터소스 uid (Grafana API)
$pw = terraform output -raw grafana_admin_password       # set-02 만 output 있음
kubectl -n <monitoring ns> port-forward svc/monitoring-grafana 3000:80
curl.exe -s -u "admin:$pw" http://localhost:3000/api/datasources |
  ConvertFrom-Json | Select-Object name, uid, type
```

| 세트 | 데이터소스 | 비고 |
| --- | --- | --- |
| set-02 | Prometheus | `grafana_admin_user`·`grafana_admin_password` output 있음 |
| set-03 | Prometheus + **CloudWatch** (`aws_iam_role.grafana` Pod Identity) | CloudWatch 패널은 리전 지정 필요 |
| set-07 | Prometheus + **cloudwatch-exporter** (`aws_iam_role.cwexporter`) | CloudWatch 지표가 Prometheus 메트릭으로 들어온다 |

CloudWatch 데이터소스를 쓰는 패널은 IAM이 짝이다 — 권한이 없으면 패널만 비고 apply는 성공한다. → [irsa](../irsa/README.md)
</details>

## VERIFY

```powershell
kubectl get pods -n <monitoring ns>
kubectl get prometheusrule -A
kubectl get targetgroupbinding -A
"http://$(terraform output -raw grafana_alb_dns)"        # set-02 / set-07 은 grafana_alb_dns_name
```

Grafana가 기존 ALB 경로로 열리고, 요구된 PrometheusRule이 생성되며, **패널·알림 이름이 과제지와 일치**하는지 확인한다.

## TROUBLESHOOT

- **새 ALB·Target Group을 추가 생성하지 않는다** — 불필요 리소스 감점.
- `kube-prometheus-stack-values.yaml` 은 기존 values 전체를 대체하지 않는다. 필요한 섹션만 병합하고 중복을 확인한다.
- PrometheusRule의 `labels.release` 가 helm release 이름과 다르면 룰이 로드되지 않는다.
- 패널 `datasource.uid` 가 틀리면 **No Data** 가 뜬다 — apply는 성공하므로 눈으로 확인해야 한다.
- 채점이 정확한 패널 수·이름을 검사할 수 있다. 과제지가 요구하지 않은 패널·알림을 과도하게 추가하지 않는다.
- 채점 요소는 Helm 내부 상태가 아니라 **생성된 k8s 오브젝트·대시보드·노출 상태**로 검증 가능해야 한다.

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
