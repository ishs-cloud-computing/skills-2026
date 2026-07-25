# Module 4 — Container Logging (ap-northeast-1)

EKS 1.35 + OTel Collector(DaemonSet) → Loki(OTLP) → Grafana 로그 파이프라인, 앱/Grafana 는 이름 고정 ALB+TargetGroupBinding 으로 노출. terraform 은 본 PC, 클러스터·헬름·이미지 빌드는 CloudShell 에서 한다.
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
# apply 전에 과제지의 아래 이름이 terraform.tfvars·eksctl/cluster.yaml 값과 같은지 대조한다.
#   o11y-cluster / o11y-app-alb·o11y-app-tg / o11y-grafana-alb·o11y-grafana-tg
#   log-generator(o11y ns) / o11y-otel·o11y-loki·o11y-grafana(monitoring ns)
#   인스턴스 타입·노드 수·AZ 는 eksctl/cluster.yaml 에 있다.
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
export NUM=<선수등번호>
export AWS_DEFAULT_REGION=$(jq -r '.region.value' ~/module-4/outputs.json)
export REGION=$(jq -r '.region.value' ~/module-4/outputs.json)
export CLUSTER_NAME=$(jq -r '.cluster_name.value' ~/module-4/outputs.json)
export LBC_POLICY_ARN=$(jq -r '.lbc_policy_arn.value' ~/module-4/outputs.json)
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
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"

# 5) AWS Load Balancer Controller 3.4.2 — TargetGroupBinding CRD 제공
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version 3.4.2 \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION" --set vpcId=$VPC_ID
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
# 3패널 모두 데이터가 있어야 한다 — No Data 패널이 하나라도 있으면 4-6 오답이다.
for L in info warn error; do curl -s "http://$APP_ALB/log?level=$L&count=3"; done
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

`eksctl create`(~20분) 중 브라우저 탭을 닫지 않는다. 세션이 끊겼으면 재접속 후 `source ~/.o11y-env` 로 이어서 진행한다.

## 참고

- 설계 근거: `docs/src/content/docs/setlist/set-07/task-2/deployment.md`
- 채점 항목 ↔ 구현 매핑: 같은 경로의 `mapping.md`
- 함정·미해결 항목: [../NOTES.md](../NOTES.md)
