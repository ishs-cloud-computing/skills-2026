# Module 3 — EKS Scaling (ap-northeast-2)

SQS + EKS 1.35 + KEDA(Pod 스케일) + Karpenter(Node 스케일). terraform 은 본 PC, 클러스터/헬름/이미지 빌드는 bastion 에서 한다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (bastion/CloudShell 단계는 공통).

## 디렉토리 구조

```
module-3-eks-scaling/
├── terraform/            # VPC, Bastion(docker 설치), SQS, ECR, KEDA/Karpenter/App IAM
├── eksctl/cluster.yaml   # skm-eks-cluster 1.35, addon NG(taint), IRSA, public+private endpoint
└── k8s/
    ├── 00-namespace.yaml
    ├── 10-karpenter-nodepool.yaml   # EC2NodeClass skm-app-nodeclass + NodePool skm-app-nodepool
    ├── 20-deployment.yaml           # order-processor (<ECR_IMAGE>/<SQS_URL> 치환)
    └── 30-keda-scaledobject.yaml    # order-scaler (<SQS_URL> 치환)

# 앱 소스: ../provided/Module3-EKS-Scaling/ (제공 app.py/Dockerfile, 수정 금지) — bastion 에서 그대로 빌드
# 채점: ../mark/mark3.sh (CloudShell 에서 실행)
```

## 배포 순서

```powershell
# ===== 본 PC =====
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json

# bastion 전송 (terraform/ 는 보내지 않음 — provider 수백 MB. 비밀번호 Skill53##)
$BIP = terraform output -raw bastion_public_ip
ssh ec2-user@$BIP "mkdir -p ~/module-3"
scp -r ..\eksctl ..\k8s ..\..\mark ..\..\provided\Module3-EKS-Scaling outputs.json "ec2-user@${BIP}:~/module-3/"
ssh ec2-user@$BIP
```

```bash
# ===== 이하 bastion 에서 실행 =====
cd ~/module-3

# 1) 자격증명 — 반드시 선수 IAM 키 입력. 클러스터 생성자 = 채점 CloudShell 신원이 되어야
#    채점 셸의 kubectl-connect 가 동작한다 (~/.aws 가 인스턴스 프로파일보다 우선).
aws configure        # region: ap-northeast-2

# 2) 환경 변수 (재접속 대비 .bashrc 영구화 — 작업규칙 6)
cat > ~/.skm-env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export ACCOUNT_ID=$(jq -r '.account_id.value' outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["skm-subnet-priv-a"]' outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["skm-subnet-priv-c"]' outputs.json)
export SQS_URL=$(jq -r '.sqs_queue_url.value' outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' outputs.json)
EOF
grep -qxF 'source ~/.skm-env' ~/.bashrc || echo 'source ~/.skm-env' >> ~/.bashrc
source ~/.skm-env

# 3) EKS 클러스터 (~20분)
cd eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
kubectl get nodes -L dedicated       # addon 노드 1대 (dedicated=addon)

# 4) 앱 이미지 빌드/푸시 (제공 Dockerfile 그대로. docker 그룹 미반영이면 sg docker -c '...' 또는 재로그인)
cd ../Module3-EKS-Scaling
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"

# 5) KEDA 2.20.1 — keda-operator SA 재사용(IRSA), addon 노드 taint toleration
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.20.1 \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.name=keda-operator \
  --set 'tolerations[0].key=CriticalAddonsOnly' \
  --set 'tolerations[0].operator=Exists'
kubectl get pods -n keda             # 3개 모두 Running (Pending 이면 toleration 미적용 — 주의 참조)

# 6) Karpenter 1.14.0 — kube-system (채점 3-5). CriticalAddonsOnly toleration 은 차트 기본값.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --version 1.14.0 \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName=skm-eks-cluster \
  --set settings.interruptionQueue="" \
  --set replicas=1 \
  --set controller.resources.requests.cpu=0.5 \
  --set controller.resources.requests.memory=512Mi
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter   # 1개 Running

# 7) k8s 오브젝트 (번호 순서대로 — NodePool 이 먼저 있어야 앱 Pod 가 스케줄된다)
cd ~/module-3/k8s
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-karpenter-nodepool.yaml
sed -e "s|<ECR_IMAGE>|$ECR:v1.0.0|g" -e "s|<SQS_URL>|$SQS_URL|g" 20-deployment.yaml | kubectl apply -f -
sed "s|<SQS_URL>|$SQS_URL|g" 30-keda-scaledobject.yaml | kubectl apply -f -

# 8) 검증 — Karpenter 가 노드 1대를 띄우고 앱 Pod 가 Ready 될 때까지 ~2분
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool    # 1대
kubectl get pods -n skillsmkt -o wide                          # order-processor 1/1 Running
kubectl get scaledobject -n skillsmkt                          # order-scaler READY True
```

```bash
# ===== CloudShell (ap-northeast-2) =====
# Actions → Upload file 로 ../mark/mark3.sh 업로드 후
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2
bash mark3.sh
# 3-6: 메시지 100건 주입 → 3분 관찰 → Max Ready Pods 5 / Max App Nodes 2 이상
# 3-7: purge → 3분 관찰 → Final Pods 1 / Final Nodes 1
```

## 요구사항 ↔ 구현 매핑 (채점지 3)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 3-1 | SQS `skm-order-queue` | `terraform/sqs.tf` |
| 3-2 | 클러스터 1.35 / addon NG 1/1/1 t3.medium / 노드 Name 태그 | `eksctl/cluster.yaml` |
| 3-3 | order-processor (replicas/port/requests/env, NodePool 배치) | `k8s/20-deployment.yaml` |
| 3-4 | KEDA(keda ns) + order-scaler 1~5 / qlen 5 | 배포 5) + `k8s/30-keda-scaledobject.yaml` |
| 3-5 | Karpenter(kube-system) + NodePool/NodeClass/taint/consolidation | 배포 6) + `k8s/10-karpenter-nodepool.yaml` |
| 3-6 | 스케일아웃 (Pod ≥5, Node ≥2) | `20`,`10` (500m×5 는 노드 1대에 수용 불가) |
| 3-7 | 스케일인 (Pod 1, Node 1) | `30`(scaleDown 30s) + `10`(consolidate 60s) |

## 주의 / 검증 포인트

- **이름 정확 일치**: `skm-order-queue`, `skm-eks-cluster`, `skm-cluster-addon-ng`(+노드 태그 `skm-cluster-addon-ng-node`), `order-processor`, `order-scaler`, `skm-app-nodepool`, `skm-app-nodeclass`.
- **클러스터 생성 전 `aws configure` 필수** — 인스턴스 프로파일 신원으로 만들면 채점 CloudShell 에서 kubectl 인증이 안 된다. 이미 만들었다면 `aws eks create-access-entry` + `associate-access-policy` 로 선수 IAM ARN 에 AmazonEKSClusterAdminPolicy 를 부여한다.
- deployment env 는 리터럴 3개만 유지한다(채점 3-3 이 name=value 로 정확 비교). valueFrom/추가 env 금지.
- 채점 3-7 의 대기는 최대 2.5분이다. ScaledObject 의 `stabilizationWindowSeconds: 30` 과 NodePool 의 `consolidateAfter: 60s` 를 늘리면 시간 내 1/1 수렴에 실패할 수 있다.
- KEDA 차트의 `tolerations` 값이 컴포넌트별 키로 바뀌었으면(`operator.tolerations` 등) `kubectl get pods -n keda` 가 Pending 으로 남는다. 그때는 `helm show values kedacore/keda --version 2.20.1 | grep -n -A3 tolerations` 로 현재 키를 확인해 다시 설치한다 (작업규칙 7).
- **과제 종료 전** 부하를 모두 중지해 Pod 1 / Karpenter 노드 1 상태로 만든다 (과제지 ⚠️).
- mark3.sh 는 자격증명을 건드리지 않지만(해당 줄 주석) kubeconfig 는 만들지 않는다 — CloudShell 에서 `aws eks update-kubeconfig` 를 먼저 실행한다.
