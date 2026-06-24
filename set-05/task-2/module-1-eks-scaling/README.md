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

```bash
# 1) Terraform — VPC / Bastion / SQS / IAM
cd terraform
terraform init && terraform apply -auto-approve

# 2) eksctl 환경변수 + 클러스터 생성
export ACCOUNT_ID=$(terraform output -raw account_id)
export VPC_ID=$(terraform output -raw vpc_id)
export PRIV_SUBNET_A=$(terraform output -json private_subnet_ids | jq -r '.["wsc-scaling-sn-priv-a"]')
export PRIV_SUBNET_C=$(terraform output -json private_subnet_ids | jq -r '.["wsc-scaling-sn-priv-c"]')
cd ../eksctl
envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml

# 3) KEDA 설치 (eksctl 가 만든 keda-operator SA 재사용)
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm upgrade --install keda kedacore/keda -n keda \
  --set serviceAccount.create=false --set serviceAccount.name=keda-operator

# 4) Karpenter 설치 (eksctl 가 만든 karpenter SA 재사용)
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n karpenter \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName=wsc-scaling-cluster \
  --set settings.interruptionQueue="" \
  --set controller.resources.requests.cpu=0.5 --set controller.resources.requests.memory=512Mi

# 5) k8s 오브젝트 (SQS_URL 치환 후 apply)
cd ../terraform
SQS_URL=$(terraform output -raw sqs_queue_url)
cd ../k8s
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-deployment.yaml
sed "s|<SQS_URL>|$SQS_URL|g" 20-keda-scaledobject.yaml | kubectl apply -f -
kubectl apply -f 30-karpenter-nodepool.yaml

# 6) 셀프 채점 (Bastion) — 공식 채점 스크립트 (task-2/mark/)
bash ../../mark/mark1.sh
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
- Karpenter 노드가 클러스터에 조인하려면 노드 역할 인증이 필요하다. EKS Access Entry 모드에서 eksctl 가 자동 처리하지 못하면 다음을 1회 실행한다:
  ```bash
  eksctl create accessentry --cluster wsc-scaling-cluster --region ap-northeast-2 \
    --principal-arn arn:aws:iam::$ACCOUNT_ID:role/KarpenterNodeRole-wsc-scaling-cluster \
    --type EC2_LINUX
  ```
