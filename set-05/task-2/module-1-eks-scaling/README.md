# Module 1 — EKS Scaling (ap-northeast-2)

EKS + KEDA(SQS 기반 Pod 스케일) + Karpenter(Node 스케일) 환경. Bastion에서 EKS 오브젝트를 배포/채점한다.

## 디렉토리 구조

```
module-1-eks-scaling/
├── terraform/        # VPC, Bastion(EIP+Admin), SQS, KEDA/Karpenter IAM
├── eksctl/cluster.yaml   # wsc-scaling-cluster, 단일 NodeGroup wsc-scaling-node, IRSA
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 10-deployment.yaml          # wsc-scaling-deploy (busybox sleep)
│   ├── 20-keda-scaledobject.yaml   # <SQS_URL> 치환
│   └── 30-karpenter-nodepool.yaml  # EC2NodeClass + NodePool (CPU 100 / Mem 200Gi)
└── README.md

(채점: 상위 ../mark/mark1.sh — 공식 채점 스크립트)
```

## 배포 순서

```powershell
# ===== 본컴(local·PowerShell) =====
# 1) Terraform — VPC / Bastion / SQS / IAM
cd terraform
terraform init && terraform apply -auto-approve
terraform output -json > outputs.json          # bastion 전송용 (수 KB)

# 2) bastion 으로 필요한 것만 전송 (terraform/ 는 보내지 않음 → 876MB provider 미전송)
$BASTION = "ec2-user@$(terraform output -raw bastion_public_ip)"
ssh $BASTION "mkdir -p ~/module-1"
scp -r ..\eksctl ..\k8s ..\..\mark outputs.json "${BASTION}:~/module-1/"
ssh $BASTION
```

```bash
# ===== 이하 bastion 에서 실행 =====
cd ~/module-1
command -v envsubst >/dev/null || sudo dnf -y install gettext   # user_data 가 안 깔아줌

# 3) eksctl 환경변수 + 클러스터 생성 (값은 outputs.json 에서 jq 로 읽음)
export ACCOUNT_ID=$(jq -r '.account_id.value' outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["wsc-scaling-sn-priv-a"]' outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["wsc-scaling-sn-priv-c"]' outputs.json)
# 재접속 대비 .bashrc 영구화 (CLAUDE.md 작업규칙 4)
printf 'export ACCOUNT_ID=%s\nexport VPC_ID=%s\nexport PRIV_SUBNET_A=%s\nexport PRIV_SUBNET_C=%s\n' \
  "$ACCOUNT_ID" "$VPC_ID" "$PRIV_SUBNET_A" "$PRIV_SUBNET_C" >> ~/.bashrc
cd eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml

# 4) KEDA 설치 (eksctl 가 만든 keda-operator SA 재사용)
# 차트 2.20.x 는 flat serviceAccount.create/name 이 deprecated(무시됨) → 컴포넌트별 키 사용.
# SQS 권한(IRSA)이 필요한 건 operator 뿐이므로 그것만 기존 SA 로 고정(create=false 로 소유권 충돌도 회피),
# metricServer/webhooks 는 Helm 이 자체 SA 를 만든다.
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm upgrade --install keda kedacore/keda -n keda --version 2.20.1 \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.name=keda-operator

# 5) Karpenter 설치 (eksctl 가 만든 karpenter SA 재사용)
# k8s 매니페스트가 karpenter.sh/v1 CRD 를 쓰므로 차트는 반드시 1.x 로 고정한다.
# 차트 1.13.0 은 flat serviceAccount.create/name 을 그대로 쓰므로 create=false 가 정상 적용된다.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n karpenter --version 1.13.0 \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName=wsc-scaling-cluster \
  --set settings.interruptionQueue="" \
  --set controller.resources.requests.cpu=0.5 --set controller.resources.requests.memory=512Mi

# 6) k8s 오브젝트 (SQS_URL 치환 후 apply)
SQS_URL=$(jq -r '.sqs_queue_url.value' ~/module-1/outputs.json)
cd ~/module-1/k8s
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-deployment.yaml
sed "s|<SQS_URL>|$SQS_URL|g" 20-keda-scaledobject.yaml | kubectl apply -f -
kubectl apply -f 30-karpenter-nodepool.yaml

# 7) 셀프 채점 (Bastion) — 공식 채점 스크립트 (task-2/mark/)
bash ~/module-1/mark/mark1.sh
```

> Karpenter 컨트롤러는 자기 자신이 스케줄될 노드가 필요하므로 ManagedNodeGroup(min 2) 위에서 동작한다.
> NodePool 의 `dedicated=scaling` 라벨 + Deployment 의 `nodeSelector` 로 신규 노드에도 Pod 가 분산된다.

## 요구사항 ↔ 구현 매핑 (채점지 1)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 1-1 | 인프라 구성 (VPC/Subnet/Bastion/SQS) | `terraform/vpc.tf`, `bastion.tf`, `sqs.tf` |
| 1-2 | EKS 구성 (1.35) | `eksctl/cluster.yaml` (metadata.version) |
| 1-3 | NodeGroup (t3.medium, min2/max10, label) | `eksctl/cluster.yaml` managedNodeGroups |
| 1-4 | Namespace + Deployment 가용성 | `k8s/00-namespace.yaml`, `10-deployment.yaml` |
| 1-5 | KEDA SQS 스케일 (interval 30, qlen 5) | `k8s/20-keda-scaledobject.yaml` |
| 1-6 | KEDA+Karpenter 스케일 테스트 | `k8s/20`,`30` + `mark1.sh` |

## 주의 / 검증 포인트

- **이름 정확 일치**: cluster `wsc-scaling-cluster`, nodegroup/노드명 `wsc-scaling-node`, SQS `wsc-scaling-sqs`, ScaledObject `wsc-scaling-scaledobject`.
- KEDA 트리거는 `queueLength: 5` → 메시지 100건이면 desired ≈ 20 (채점지 1-6: Pod 19~20개).
- Karpenter NodePool 노드 타입을 t3.medium 로 제한해 Pod 20개 → 노드 약 4개(기본 2 + 신규 2)로 수렴.
- `identityOwner: operator` 로 KEDA가 keda-operator IRSA 역할의 SQS 권한을 사용한다.
- Karpenter 노드(KarpenterNodeRole)의 클러스터 조인용 EKS access entry 는 `cluster.yaml` 의 `accessConfig.accessEntries` 에 내장되어 클러스터 생성 시 자동 처리된다. 별도 수동 단계 불필요.
