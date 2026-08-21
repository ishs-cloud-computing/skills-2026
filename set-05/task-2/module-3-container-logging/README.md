# Module 3 — Container Logging (ap-northeast-1)

EC2의 Docker 컨테이너(Flask) 로그를 호스트 Fluent Bit이 수집해 EKS의 Loki로 전송하고 Grafana로 시각화한다. 로그 발생→대시보드 도달 10초 이내.

## 디렉토리 구조

```
module-3-container-logging/
├── terraform/        # VPC, App EC2(docker+fluent-bit), IAM
├── eksctl/cluster.yaml   # wsc-logging-cluster, wsc-logging-ng (min2/max4)
├── k8s/
│   ├── 00-namespace.yaml  01-storageclass.yaml
│   ├── loki-values.yaml   loki-lb-service.yaml   # SingleBinary + NLB 3100
│   ├── grafana-values.yaml  dashboard.json        # NLB + WSC2026 대시보드 4패널
├── app/fluent-bit.conf   # Fluent Bit 호스트 설정 (제공 외 자체 작성)
└── README.md

# 앱 소스: task-2/provided/2-3/{app.py,requirements.txt,Dockerfile} (제공 배포파일, 수정 금지) — terraform 가 직접 참조
# 채점: task-2/mark/mark3.sh (공식 채점 스크립트 — kubectl·aws 가 있는 본 PC git-bash 에서 실행. 이 모듈의 EC2 는 kubectl 이 없다)
```

## 파이프라인

```
EC2(wsc-log-app-bastion)
  └ docker[wsc-log-app:5000] --(json-file)--> /var/lib/docker/containers/*/*.log
       └ Fluent Bit(systemd) tail -> record_modifier(namespace=wsc-app-log) -> Loki NLB:3100
EKS(wsc-logging-cluster)
  └ Loki(SingleBinary, PVC 10Gi)  <- Grafana(Loki DataSource) -> WSC2026 Container Logs
```

## 배포 순서

전 단계 본 PC(PowerShell 7). 채점 스크립트만 git-bash.

```powershell
# 1) Terraform — VPC / App EC2 / IAM
cd terraform
terraform init && terraform apply -auto-approve

# 2) eksctl 클러스터 (placeholder 치환 — 본 PC 에는 envsubst 가 없다)
$outs = terraform output -json | ConvertFrom-Json
cd ..\eksctl
$y = Get-Content -Raw cluster.yaml
$y = $y.Replace('${VPC_ID}', $outs.vpc_id.value)
$y = $y.Replace('${PRIV_SUBNET_A}', $outs.private_subnet_ids.value.'wsc-logging-sn-priv-a')
$y = $y.Replace('${PRIV_SUBNET_C}', $outs.private_subnet_ids.value.'wsc-logging-sn-priv-c')
$y = $y.Replace('${PUB_SUBNET_A}', $outs.public_subnet_ids.value.'wsc-logging-sn-pub-a')
$y = $y.Replace('${PUB_SUBNET_C}', $outs.public_subnet_ids.value.'wsc-logging-sn-pub-c')
$y | Set-Content cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml

# 3) Loki + Grafana (helm)
cd ..\k8s
kubectl apply -f 00-namespace.yaml -f 01-storageclass.yaml
# OSS Loki 차트는 2026-03-16부로 grafana-community 저장소로 이전됨(grafana/loki 는 GEL 전용).
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm upgrade --install loki grafana-community/loki -n wsc-logging --version 18.1.1 -f loki-values.yaml
kubectl apply -f loki-lb-service.yaml

$NM = '<비번호>'
(Get-Content -Raw grafana-values.yaml).Replace('__NM__', $NM) | Set-Content grafana-values.rendered.yaml
kubectl -n wsc-logging create configmap wsc-dashboard --from-file=dashboard.json=dashboard.json
helm upgrade --install grafana grafana/grafana -n wsc-logging --version 10.5.15 -f grafana-values.rendered.yaml

# 4) Fluent Bit → Loki 엔드포인트 연결 (Loki NLB 생성 후)
$LOKI_LB = kubectl get svc -n wsc-logging loki-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
$INSTANCE_ID = aws ec2 describe-instances --region ap-northeast-1 --filters "Name=tag:Name,Values=wsc-log-app-bastion" --query "Reservations[0].Instances[0].InstanceId" --output text
aws ssm send-command --region ap-northeast-1 --instance-ids $INSTANCE_ID `
  --document-name AWS-RunShellScript `
  --parameters "{`"commands`":[`"sed -i s/__LOKI_HOST__/$LOKI_LB/ /etc/fluent-bit/fluent-bit.conf`",`"systemctl restart fluent-bit`"]}"

# 5) 셀프 채점 — bash 스크립트라 git-bash 로 실행 (kubeconfig 는 eksctl 이 이미 로컬에 기록)
bash ../../mark/mark3.sh
```

## 요구사항 ↔ 구현 매핑 (채점지 3)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 3-1 | 인프라(VPC/EKS/NodeGroup) | `terraform/vpc.tf`, `eksctl/cluster.yaml` |
| 3-2 | Loki/Grafana Pod + NLB | `k8s/loki-values.yaml`,`loki-lb-service.yaml`,`grafana-values.yaml` |
| 3-3 | EC2 Docker 컨테이너 | `provided/2-3/{app.py,Dockerfile}` + `terraform/ec2.tf` |
| 3-4 | Fluent Bit systemd | `app/fluent-bit.conf` + `terraform/ec2-userdata.sh.tftpl` |
| 3-5 | E2E 로그 수집 | 전체 파이프라인 |
| 3-6 | Grafana 4패널 대시보드 | `k8s/dashboard.json`,`grafana-values.yaml` |

## 주의 / 검증 포인트

- **이름 정확 일치**: cluster `wsc-logging-cluster`, nodegroup `wsc-logging-ng`/노드 `wsc-logging-node`, namespace `wsc-logging`, container `wsc-log-app`. **EC2 Name은 `wsc-log-app-bastion`** (과제지는 `wsc-logging-app-bastion`이나 공식 mark3.sh가 `wsc-log-app-bastion`으로 조회하므로 채점 스크립트에 맞춤).
- **로그 레이블 `namespace=wsc-app-log`** 은 EKS Namespace가 아니라 Fluent Bit `record_modifier`가 주입하는 값이다.
- Loki/Grafana NLB는 `service.type: LoadBalancer` + `aws-load-balancer-type: nlb` 로 EKS Cloud Controller가 internet-facing NLB를 생성한다(LB Controller 불필요). public 서브넷에 `kubernetes.io/role/elb` 태그 필요.
- Fluent Bit의 Loki Host는 NLB 생성 후 알 수 있으므로 **배포 후 4단계**에서 `__LOKI_HOST__` 를 치환하고 재시작한다. (재시작 전에도 systemd 서비스는 active → 3-4 통과)
- Grafana admin: ID `wsc2026-admin-{비번호}`, PW `admin{비번호}!`. 대시보드 4종 LogQL은 `dashboard.json` 의 패널과 정확히 일치.
- 앱(`provided/2-3/app.py`)은 제공 Flask 앱(수정 금지)이며 `/health`,`/`,`/generate`,`/error` 응답 형식은 Flask `jsonify` 출력 그대로다(채점지 표기 차이는 제공 앱 출력 기준).
- 제공 Dockerfile은 TZ 미설정이므로 `docker run`에서 `TZ=Asia/Seoul` + zoneinfo 마운트로 KST 타임스탬프를 적용한다.
