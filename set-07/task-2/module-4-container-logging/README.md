# Module 4 — Container Logging (ap-northeast-1)

EKS 1.35 + OTel Collector(DaemonSet) → Loki(OTLP) → Grafana 로그 파이프라인, 앱/Grafana 는 이름 고정 ALB+TargetGroupBinding 으로 노출. terraform 은 본 PC, 클러스터/헬름/이미지 빌드는 CloudShell 에서 한다(CloudShell 에 Docker 내장).
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-4-container-logging/
├── terraform/            # VPC, ALB/TG(이름 고정), ECR, LBC IAM
├── eksctl/cluster.yaml   # o11y-cluster 1.35, NG 2/2/2 Multi-AZ, KST, EBS CSI, LBC IRSA
├── app/Dockerfile        # 자체 작성 (제공 Dockerfile 은 flask 미설치로 기동 불가)
└── k8s/
    ├── 00-namespaces.yaml 01-storageclass.yaml
    ├── app/         # log-generator Deployment/Service/TargetGroupBinding
    ├── logging/     # OTel Collector RBAC/ConfigMap/DaemonSet (o11y-otel)
    └── monitoring/  # loki-values, grafana-values, dashboard.json, grafana TGB

# 앱 소스: ../provided/Module4-Container-Logging/app.py (제공 파일, 수정 금지) — 빌드 시 복사
# 채점: ../mark/mark4.sh (CloudShell 에서 실행)
```

## 배포 순서

```powershell
# ===== 본 PC =====
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json

# CloudShell 반입용 zip (terraform/ 는 넣지 않음 — provider 수백 MB)
Compress-Archive -Force -DestinationPath ..\module-4.zip `
  -Path ..\eksctl, ..\k8s, ..\app, ..\..\mark, ..\..\provided\Module4-Container-Logging, outputs.json
# → CloudShell(ap-northeast-1) 접속 후 Actions → Upload file 로 module-4.zip 업로드
```

```bash
# ===== 이하 CloudShell (ap-northeast-1) 에서 실행 =====
# 채점과 같은 셸이므로 클러스터 생성자 신원 = 채점 신원이 자동 일치한다 (aws configure 불필요).

# 0) 반입 파일 풀기
mkdir -p ~/module-4 && cd ~/module-4
unzip -o ~/module-4.zip     # eksctl/ k8s/ app/ mark/ Module4-Container-Logging/ outputs.json

# 1) 툴 설치 — kubectl·aws·docker 는 CloudShell 기본. eksctl·helm 만 ~/bin 에.
mkdir -p ~/bin
grep -qxF 'export PATH=$HOME/bin:$PATH' ~/.bashrc || echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
export PATH=$HOME/bin:$PATH
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C ~/bin
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=$HOME/bin USE_SUDO=false bash

# 2) 환경 변수 (재접속 대비 ~/.bashrc 영구화 — 작업규칙 6, CloudShell $HOME 영속)
cat > ~/.o11y-env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-1
export NUM=<선수등번호>
export ACCOUNT_ID=$(jq -r '.account_id.value' ~/module-4/outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' ~/module-4/outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["o11y-subnet-priv-a"]' ~/module-4/outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["o11y-subnet-priv-c"]' ~/module-4/outputs.json)
export NODE_EXTRA_SG_ID=$(jq -r '.node_extra_sg_id.value' ~/module-4/outputs.json)
export APP_TG_ARN=$(jq -r '.app_target_group_arn.value' ~/module-4/outputs.json)
export GRAFANA_TG_ARN=$(jq -r '.grafana_target_group_arn.value' ~/module-4/outputs.json)
export APP_ALB=$(jq -r '.app_alb_dns.value' ~/module-4/outputs.json)
export GRAFANA_ALB=$(jq -r '.grafana_alb_dns.value' ~/module-4/outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' ~/module-4/outputs.json)
EOF
grep -qxF 'source ~/.o11y-env' ~/.bashrc || echo 'source ~/.o11y-env' >> ~/.bashrc
source ~/.o11y-env

# 3) EKS 클러스터 (~20분 — 브라우저 탭 유지)
cd ~/module-4/eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
kubectl get nodes -o wide     # 2대, AZ 가 a/c 로 나뉘어야 함 (Multi-AZ, 채점 4-1)

# 4) 앱 이미지 빌드/푸시 (제공 app.py + 자체 Dockerfile, CloudShell 내장 Docker)
mkdir -p /tmp/o11y-build
cp ~/module-4/Module4-Container-Logging/app.py ~/module-4/app/Dockerfile /tmp/o11y-build/
cd /tmp/o11y-build
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"

# 5) AWS Load Balancer Controller 3.4.2 — TargetGroupBinding CRD 제공
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version 3.4.2 \
  --set clusterName=o11y-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-1 --set vpcId=$VPC_ID
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller

# 6) 네임스페이스 / StorageClass / 앱
cd ~/module-4/k8s
kubectl apply -f 00-namespaces.yaml -f 01-storageclass.yaml
sed "s|<ECR_IMAGE>|$ECR:v1.0.0|g" app/10-deployment.yaml | kubectl apply -f -
kubectl apply -f app/11-service.yaml
sed "s|<APP_TG_ARN>|$APP_TG_ARN|g" app/12-targetgroupbinding.yaml | kubectl apply -f -

# 7) Loki 18.5.1 (Single Binary + PV + OTLP 수신)
helm repo add grafana https://grafana.github.io/helm-charts
# OSS Loki 차트는 grafana-community 저장소에 있다 (grafana/loki 는 GEL 전용)
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm upgrade --install o11y-loki grafana-community/loki -n monitoring --version 18.5.1 \
  -f monitoring/loki-values.yaml
kubectl get svc o11y-loki -n monitoring        # ClusterIP 3100 (채점 4-3)

# 8) OTel Collector (Loki 이후 — otlphttp 전송 대상)
kubectl apply -f logging/
kubectl get ds o11y-otel -n monitoring         # DESIRED 2 / READY 2

# 9) Grafana 10.5.15 (__NM__ = 선수등번호 치환, 대시보드 ConfigMap)
sed "s/__NM__/$NUM/g" monitoring/grafana-values.yaml > /tmp/grafana-values.yaml
kubectl -n monitoring create configmap o11y-dashboard \
  --from-file=dashboard.json=monitoring/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install o11y-grafana grafana/grafana -n monitoring --version 10.5.15 \
  -f /tmp/grafana-values.yaml
sed "s|<GRAFANA_TG_ARN>|$GRAFANA_TG_ARN|g" monitoring/30-grafana-targetgroupbinding.yaml | kubectl apply -f -

# 10) E2E 검증 (TG healthy 까지 1~2분)
curl -s "http://$APP_ALB/healthz"                        # {"status":"ok"}
curl -s "http://$APP_ALB/log?level=error&count=3"        # {"generated":3,"level":"error"}
kubectl port-forward -n monitoring svc/o11y-loki 3100:3100 >/dev/null 2>&1 & sleep 2
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' \
  --data-urlencode "start=$(date -d '3 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" | jq -r '.data.result[].values[][1]' | head -3
kill %1                                                  # {"ts":...,"level":"ERROR",...} 출력 확인
echo "Grafana: http://$GRAFANA_ALB (skills$NUM / GoodJob!Skills$NUM^^)"
# 브라우저에서 Log Overview 대시보드 3패널 (No Data 없음, 범례 INFO/WARN/ERROR) 확인

# ===== 채점 (같은 CloudShell) =====
bash ~/module-4/mark/mark4.sh        # 4-1 이 update-kubeconfig 를 자체 수행
# 4-5 는 스크립트 하단 주석 블록을 수동 실행, 4-6 은 Grafana 웹 접속 수동 채점
```

## 요구사항 ↔ 구현 매핑 (채점지 4)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 4-1 | 클러스터 1.35 / NG t3.medium 2/2/2 Multi-AZ / KST | `eksctl/cluster.yaml` |
| 4-2 | ALB·TG 이름 고정 + 타깃 healthy | `terraform/alb.tf` + `k8s/app/12-`,`monitoring/30-*targetgroupbinding.yaml` |
| 4-3 | log-generator 2 / ds o11y-otel / svc o11y-loki 3100 / deploy o11y-grafana | `k8s/app/`, `k8s/logging/`, `loki-values.yaml`, `grafana-values.yaml` |
| 4-4 | /healthz, /log API | 제공 `app.py` + `app/Dockerfile` |
| 4-5 | OTLP 파이프라인 + LogQL(k8s_namespace_name/level) | `k8s/logging/21-otel-configmap.yaml`, `loki-values.yaml` |
| 4-6 | Grafana 로그인/Datasource/Log Overview 3패널 | `grafana-values.yaml`, `monitoring/dashboard.json` |

## 주의 / 검증 포인트

- **이름 정확 일치**: `o11y-cluster`, `o11y-app-alb`/`o11y-app-tg`, `o11y-grafana-alb`/`o11y-grafana-tg`, `log-generator`(o11y), `o11y-otel`/`o11y-loki`/`o11y-grafana`(monitoring).
- **클러스터는 채점과 같은 CloudShell 에서 생성**한다 — 생성자 신원 = 채점 신원이 자동 일치.
- ALB/TG 이름은 채점이 "이름"으로 조회하므로 LBC Ingress(이름 지정 불가)가 아니라 terraform ALB + TargetGroupBinding 으로 만든다. TGB 는 LBC 설치(5) 이후에만 apply 가능하다.
- 제공 Dockerfile 은 flask 를 설치하지 않아 그대로 빌드하면 Pod 가 CrashLoop 된다 — 반드시 `app/Dockerfile` 로 빌드한다 (제공 `app.py` 는 수정 금지).
- 채점 4-5 의 LogQL 라벨은 `k8s_namespace_name` (OTLP 리소스 속성 승격), level 값은 대문자 `ERROR` 다. OTel 이 본문을 가공하면 `| json` 파싱이 깨지므로 filelog 의 `container` 파서 외 본문 변형을 추가하지 않는다.
- Grafana 범례가 `{level="ERROR"}` 형태로 보이면 4-6 오답 — 대시보드 쿼리는 `sum by (level)` + `legendFormat {{level}}` 을 유지한다. 채점 전 `/log` 를 각 레벨로 한 번씩 호출해 3패널 모두 데이터가 있게 한다 (No Data 패널 = 오답).
- `mark4.sh` 는 `rm -rf ~/.aws` 를 수행하지만 CloudShell 자격증명은 관리형 세션(`~/.aws` 아님)이라 무해하다. `~/bin`·`~/.o11y-env` 도 영향 없다.
- **CloudShell 세션**은 브라우저 탭에 묶인다 — `eksctl create`(~20분) 중 탭을 닫지 않는다. 재접속 후엔 `source ~/.o11y-env` 만 하면 된다.
