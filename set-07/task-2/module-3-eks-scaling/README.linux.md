# 본 PC 가 Linux 일 때의 런북 (module-3-eks-scaling)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. Linux 는 `envsubst`/`sed` 를 그대로 써서
치환이 간단하다. **CloudShell 단계(이미지 빌드 + 채점)는 README.md 와 동일.**

```bash
# ===== 본 PC =====
# 0) 툴: eksctl·helm·kubectl 이 있어야 한다 (없으면 각 공식 설치).

# 1) terraform
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json
cd ..

# 2) cluster.yaml 치환 → cluster.rendered.yaml
export ACCOUNT_ID=$(jq -r '.account_id.value' terraform/outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' terraform/outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["skm-subnet-priv-a"]' terraform/outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["skm-subnet-priv-c"]' terraform/outputs.json)
export SQS_URL=$(jq -r '.sqs_queue_url.value' terraform/outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' terraform/outputs.json)
envsubst < eksctl/cluster.yaml > eksctl/cluster.rendered.yaml
grep -q '\${' eksctl/cluster.rendered.yaml && echo '치환 안 된 토큰 남음' && exit 1

# 3) EKS 클러스터 (~20분 — 본 PC 셸이라 유휴 회수 없음)
eksctl create cluster -f eksctl/cluster.rendered.yaml
kubectl get nodes -L dedicated

# 4) KEDA 2.20.1
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.20.1 \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.name=keda-operator \
  --set 'tolerations[0].key=CriticalAddonsOnly' \
  --set 'tolerations[0].operator=Exists'

# 5) Karpenter 1.14.0
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --version 1.14.0 \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName=skm-eks-cluster \
  --set settings.interruptionQueue="" \
  --set replicas=1 \
  --set controller.resources.requests.cpu=0.5 \
  --set controller.resources.requests.memory=512Mi

# 6) k8s 오브젝트 (이미지(CloudShell B)가 미리 push 돼 있어야 함)
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/10-karpenter-nodepool.yaml
sed -e "s|<ECR_IMAGE>|$ECR:v1.0.0|g" -e "s|<SQS_URL>|$SQS_URL|g" k8s/20-deployment.yaml | kubectl apply -f -
sed "s|<SQS_URL>|$SQS_URL|g" k8s/30-keda-scaledobject.yaml | kubectl apply -f -

# 7) 검증
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool
kubectl get pods -n skillsmkt -o wide
kubectl get scaledobject -n skillsmkt

# ===== CloudShell 반입 (이미지 빌드용) =====
# 제공 소스 + outputs.json 만 zip → Upload file. 이미지 빌드·채점은 README.md 의 CloudShell 단계와 동일.
rm -rf /tmp/m3 && mkdir -p /tmp/m3
cp -r ../provided/Module3-EKS-Scaling terraform/outputs.json /tmp/m3/
(cd /tmp/m3 && zip -r ~/module-3.zip .)
```
