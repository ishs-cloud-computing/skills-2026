# 본 PC 가 Linux 일 때의 런북 (module-3-eks-scaling)

본 PC 단계는 이 모듈 **전용 터미널**에서 진행한다 (터미널 1개 = 클러스터 1개, [README.md](README.md) 상단 참조).

```bash
cd module-3-eks-scaling
export KUBECONFIG="$PWD/kubeconfig"
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```bash
export KUBECONFIG="$PWD/kubeconfig"
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2 --kubeconfig "$KUBECONFIG"
```

### 1) [본 PC] Terraform

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC] EKS 클러스터 생성 (~15분)

```bash
cd ../eksctl
export ACCOUNT_ID=$(terraform -chdir=../terraform output -raw account_id)
export VPC_ID=$(terraform -chdir=../terraform output -raw vpc_id)
export PRIV_SUBNET_A=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '.["skm-eks-sn-priv-a"]')
export PRIV_SUBNET_C=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '.["skm-eks-sn-priv-c"]')
# 가드 2단계: ① envsubst 는 unset 변수도 빈 문자열로 치환하므로 치환 전 비어있음 검사
#            ② 변수 목록 명시 → 목록 외 신규 플레이스홀더는 남아서 grep 에 걸림
# 스니펫은 zsh/bash 겸용 (붙여넣기 실행 대비: exit 금지, if 게이트로만 차단)
if [ -n "$ACCOUNT_ID" ] && [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_C" ]; then
  envsubst '${ACCOUNT_ID} ${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_C}' < cluster.yaml > cluster.rendered.yaml
  if grep -n '\${' cluster.rendered.yaml; then echo "STOP: 미치환 값 존재"
  else eksctl create cluster -f cluster.rendered.yaml; fi
else echo "STOP: terraform output 값 누락"; fi
```

### 3) [CloudShell — 2단계 대기 중 병렬] 이미지 빌드 & ECR push

[README.md](README.md) 3단계를 수행한다.

### 4) [본 PC] KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.20.1 \
  --set serviceAccount.operator.create=false --set serviceAccount.operator.name=keda-operator \
  --set-json 'tolerations=[{"key":"CriticalAddonsOnly","operator":"Exists"}]'
kubectl get pods -n keda
```

### 5) [본 PC] Karpenter

```bash
# replicas=1 필수: chart 기본 2 + required anti-affinity 라 노드 1대(addon NG 1/1/1)에선 --wait 가 영원히 대기
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.14.0 -n kube-system \
  --set replicas=1 \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set settings.clusterName=skm-eks-cluster --set settings.interruptionQueue="" \
  --set controller.resources.requests.cpu=500m --set controller.resources.requests.memory=512Mi \
  --wait
```

### 6) [본 PC] k8s 리소스 apply

```bash
cd ../k8s
SQS_URL=$(terraform -chdir=../terraform output -raw sqs_queue_url)
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
# 중괄호 필수: zsh 는 "$ECR_URL:latest" 의 :l 을 소문자 modifier 로 해석해 이미지명이 "...atest" 로 깨진다
ECR_IMAGE="${ECR_URL}:latest"
mkdir -p rendered
for f in *.yaml; do
  sed -e "s|\${ECR_IMAGE}|${ECR_IMAGE}|g" -e "s|\${SQS_URL}|${SQS_URL}|g" "$f" > "rendered/$f"
done
if [ -z "$SQS_URL" ] || [ -z "$ECR_URL" ]; then echo "STOP: terraform output 값 누락"
elif grep -rn '\${' rendered/; then echo "STOP: 미치환 값 존재"
else kubectl apply -f rendered/; fi    # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
kubectl get pod -n skillsmkt -o wide -w
```

### 7) [CloudShell] 클러스터 접속 확인

[README.md](README.md) 7단계 수행. `Unauthorized` 시에만 아래를 본 PC 에서 실행:

```bash
aws eks create-access-entry --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-2
aws eks associate-access-policy --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> \
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region ap-northeast-2
```

### 8) [CloudShell] 셀프 채점

[README.md](README.md) 8단계 수행 (사전 상태: Pod 1개·Karpenter 노드 1대·빈 큐).

## Teardown

```bash
cd k8s
kubectl delete -f rendered/30-keda-scaledobject.yaml
kubectl delete -f rendered/20-deployment.yaml
kubectl delete -f rendered/10-karpenter-nodepool.yaml
cd ../eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
