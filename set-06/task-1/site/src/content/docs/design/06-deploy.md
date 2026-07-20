---
title: "배포 순서"
sidebar:
  order: 6
---

의존 관계상 **Terraform(네트워크·ECR) → 이미지 push → eksctl → Terraform(나머지) → k8s** 순서가 강제된다.
CloudFront VPC Origin은 ALB가, TargetGroupBinding은 TG가 먼저 있어야 한다.

```bash
# 0) 로컬 환경 변수
cd set-06/task-1/terraform
export AWS_REGION=ap-northeast-2

# 1) 네트워크 + ECR + KMS + DynamoDB 먼저
terraform init
terraform apply -target=aws_ecr_repository.book -target=aws_ecr_pull_through_cache_rule.public

# 2) 이미지 빌드·push (로컬 Docker Desktop, zstd 압축)
aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com
docker buildx build --platform linux/amd64 --provenance=false \
  --output type=image,name=<ECR_URL>:latest,compression=zstd,compression-level=19,force-compression=true,push=true \
  -f ../app/Dockerfile ../../../shared/provided/set-06-task-1
aws ecr describe-images --repository-name book \
  --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text   # 3145728 이하 확인

# 3) 나머지 AWS 리소스
terraform apply
terraform output -json > outputs.json

# 3.5) bootstrap container 이미지 push + 풀스루 캐시 워밍업 (인터넷 있는 로컬에서)
docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:<TAG>
docker tag ... <ECR>/gj2026/br-bootstrap:1.0.0 && docker push <ECR>/gj2026/br-bootstrap:1.0.0
docker pull <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest   # 4-5 대비

# 4) EKS 클러스터
cd ../eksctl && envsubst < cluster.yaml > cluster.rendered.yaml
eksctl create cluster -f cluster.rendered.yaml
aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes    # 이름 포맷 즉시 확인 (실패 시 self-managed nodeGroups로 fallback)

# 4.5) Pod SG 활성화 + addon 배치
kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true
aws eks update-addon --cluster-name gj2026-eks-cluster --addon-name coredns \
  --configuration-values file://addon-coredns.json --resolve-conflicts OVERWRITE

# 5) Grafana 이미지 미러링(Docker Hub 전용이라 풀스루 불가)
docker pull grafana/grafana:<TAG> && docker tag ... && docker push <ECR>/mirror/grafana:<TAG>

# 6) k8s 리소스
cd ../k8s && kubectl apply -f 00-namespace.yaml
helm upgrade --install aws-load-balancer-controller ...   # addon 노드
kubectl apply -f app/ && helm upgrade --install grafana ... && helm upgrade --install aws-for-fluent-bit ...

# 7) 채점 전 정리
#   - DynamoDB 아이템 0개 (enable_ddb_write_deny=false → 삭제 → true)
#   - CloudFront invalidation
```
