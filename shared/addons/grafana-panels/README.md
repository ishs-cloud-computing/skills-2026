# Grafana panels asset pack

Prometheus·Grafana 기반 관측성 문항에서 기존 `k8s/monitoring/` 구성에 병합하는 **자산 묶음**이다. 독립 Helm release나 독립 apply 대상이 아니며, 먼저 [상위 Observability KIT](../observability/README.md)의 경로 B를 따른다.

## 포함 파일

| 파일 | 사용 위치 |
| --- | --- |
| `kube-prometheus-stack-values.yaml` | 기존 kube-prometheus-stack values에 병합하는 overlay |
| `dashboard-panels.json` | Grafana 대시보드 패널 정의 |
| `grafana-alerting-provisioning.yaml` | Grafana unified alerting ConfigMap 데이터 |
| `grafana-targetgroupbinding.yaml` | 기존 ALB Target Group을 재사용하는 Grafana 노출 매니페스트 |
| `prometheus-rules.yaml` | PrometheusRule 알림 규칙 |

## 부착 절차

대상 세트의 `task.md`, `mark.md`, `mark*.sh`, `NOTES.md`를 먼저 읽고 과제지가 요구한 대시보드·알림·Grafana 노출 여부를 확인한다. 기존 `k8s/monitoring/`에 필요한 파일만 **복사·병합**한다. 자산을 그대로 적용하기 전에 클러스터명, namespace, StorageClass, Target Group ARN, 데이터소스 URL, 대시보드 이름을 대상 세트 값으로 바꾼다.

`kube-prometheus-stack-values.yaml`은 기존 values 전체를 대체하지 않는다. 필요한 섹션만 기존 values에 병합하고, 이미 존재하는 Grafana·Prometheus 설정과 중복되지 않는지 확인한다. `grafana-targetgroupbinding.yaml`은 새 ALB를 만들지 않고 이미 있는 Target Group을 사용한다.

```powershell
kubectl apply -f <대상>/k8s/monitoring/prometheus-rules.yaml
kubectl apply -f <대상>/k8s/monitoring/grafana-targetgroupbinding.yaml
kubectl get prometheusrule,targetgroupbinding -A
```

Helm 설치·업그레이드 순서는 대상 세트 README를 따른다. 채점 요소는 Helm 내부 상태가 아니라 생성된 Kubernetes 오브젝트, Grafana 대시보드·알림, 서비스 노출 상태로 검증 가능해야 한다.

## VERIFY

```powershell
kubectl get pods -n monitoring
kubectl get prometheusrule -A
kubectl get targetgroupbinding -A
```

Grafana가 기존 ALB 경로로 열리고, 요구된 PrometheusRule이 생성되며, 대시보드 패널과 알림 이름이 과제지와 일치하는지 확인한다. 이 검증은 기능 확인이며, 점수 판정은 해당 세트의 공식 채점 절차로 한다.

## 주의

새 ALB·Target Group을 추가 생성하면 불필요 리소스 감점 위험이 있다. 과제지가 요구하지 않으면 패널·알림 규칙을 과도하게 추가하지 말고, 기존 런북과 채점 스크립트가 정확한 패널 수나 이름을 검사하는지 먼저 확인한다.
