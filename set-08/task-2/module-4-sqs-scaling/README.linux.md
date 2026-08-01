# 본 PC가 Linux일 때의 런북 (module-4-sqs-scaling)

[README.md](README.md)의 본 PC 단계를 bash/zsh 겸용으로 옮긴 것. 번호는 README.md와 1:1 대응이며, CloudShell 단계도 자리에 그대로 유지했다.

## 0. IAM 권한 프로브 (대회 시작 직후 1회)

```bash
cat > iam-probe-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name skills-iam-probe --assume-role-policy-document file://iam-probe-trust.json
if [ $? -eq 0 ]; then
  aws iam delete-role --role-name skills-iam-probe
  if [ $? -ne 0 ]; then echo "삭제 거부 — skills-iam-probe role 잔존 상태를 감독관에게 확인"; fi
else
  echo "STOP: AccessDenied — IAM 미지급. 감독관 문의 (module-1·3·4 진행 불가)"
fi
rm -f iam-probe-trust.json
```

이 모듈에서 만드는 클러스터 전용 kubeconfig를 지금부터 사용한다 (터미널 1개 = 클러스터 1개):

```bash
cd module-4-sqs-scaling
export KUBECONFIG="$PWD/kubeconfig"
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```bash
export KUBECONFIG="$PWD/kubeconfig"
aws eks update-kubeconfig --name skills-sqs-cluster --region us-west-2 --kubeconfig "$KUBECONFIG"
source .env
```

## 1. terraform apply

```bash
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json   # 커밋 금지 (.gitignore)
```

주요 output을 세션 변수로 로드하고 `.env`(본 PC 재접속·CloudShell 업로드 겸용)로 저장한다:

```bash
export ACCOUNT_ID=$(terraform output -raw account_id)
export REGION=us-west-2
export VPC_ID=$(terraform output -raw vpc_id)
export PRIV_SUBNET_A=$(terraform output -json private_subnet_ids | jq -r '.["skills-sqs-sn-priv-a"]')
export PRIV_SUBNET_B=$(terraform output -json private_subnet_ids | jq -r '.["skills-sqs-sn-priv-b"]')
export QUEUE_URL=$(terraform output -raw queue_url)
ECR_REPO_URL=$(terraform output -raw ecr_repo_url)
# 중괄호 필수: zsh 는 "$ECR_REPO_URL:latest" 의 :l 을 소문자 modifier 로 해석해 이미지명이 깨진다
export ECR_IMAGE="${ECR_REPO_URL}:latest"
export KEDA_POLICY_ARN=$(terraform output -raw keda_policy_arn)
export KARPENTER_POLICY_ARN=$(terraform output -raw karpenter_policy_arn)
export WORKER_POLICY_ARN=$(terraform output -raw worker_policy_arn)
export NODE_ROLE_ARN=$(terraform output -raw karpenter_node_role_arn)
export NODE_ROLE_NAME=$(terraform output -raw karpenter_node_role_name)
cd ..

cat > .env <<EOF
export ACCOUNT_ID=${ACCOUNT_ID}
export REGION=${REGION}
export VPC_ID=${VPC_ID}
export PRIV_SUBNET_A=${PRIV_SUBNET_A}
export PRIV_SUBNET_B=${PRIV_SUBNET_B}
export QUEUE_URL=${QUEUE_URL}
export ECR_IMAGE=${ECR_IMAGE}
export KEDA_POLICY_ARN=${KEDA_POLICY_ARN}
export KARPENTER_POLICY_ARN=${KARPENTER_POLICY_ARN}
export WORKER_POLICY_ARN=${WORKER_POLICY_ARN}
export NODE_ROLE_ARN=${NODE_ROLE_ARN}
export NODE_ROLE_NAME=${NODE_ROLE_NAME}
EOF

source .env   # 재접속 시: module-4-sqs-scaling 디렉터리에서 `source .env` 만 다시 실행
```

## 2. cluster.yaml 렌더링 + eksctl create (~20분)

```bash
cd eksctl
mkdir -p rendered
# 가드 2단계: ① envsubst 는 unset 변수도 빈 문자열로 치환하므로 치환 전 비어있음 검사
#            ② 변수 목록 명시 → 목록 외 신규 플레이스홀더는 남아서 grep 에 걸림
# 스니펫은 zsh/bash 겸용 (붙여넣기 실행 대비: exit 금지, if 게이트로만 차단)
if [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_B" ] && [ -n "$KEDA_POLICY_ARN" ] && [ -n "$KARPENTER_POLICY_ARN" ] && [ -n "$WORKER_POLICY_ARN" ] && [ -n "$NODE_ROLE_ARN" ]; then
  envsubst '${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_B} ${KEDA_POLICY_ARN} ${KARPENTER_POLICY_ARN} ${WORKER_POLICY_ARN} ${NODE_ROLE_ARN}' < cluster.yaml > rendered/cluster.yaml
  if grep -n '\${' rendered/cluster.yaml; then echo "STOP: 미치환 값 존재"
  else eksctl create cluster -f rendered/cluster.yaml; fi
else echo "STOP: terraform output 값 누락"; fi
cd ..
```

## 3. [CloudShell — 2단계 eksctl 생성 대기 중 병렬] worker 이미지 build/push

[README.md](README.md) 3단계를 수행한다.

## 4. helm — Karpenter·KEDA (버전 미핀: 최신 안정)

```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter -n karpenter \
  --set settings.clusterName=skills-sqs-cluster \
  --set serviceAccount.create=false --set serviceAccount.name=karpenter \
  --set replicas=1 --set dnsPolicy=Default --wait
  # dnsPolicy=Default: Fargate 기동 시 CoreDNS 의존 제거 (VPC 리졸버 직행)

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda -n keda \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.name=keda-operator --wait
```

확인:

```bash
kubectl get pods -n karpenter
kubectl get pods -n keda
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate
```

## 5. k8s manifest 렌더링 + apply

```bash
cd k8s
if [ -z "$ECR_IMAGE" ] || [ -z "$QUEUE_URL" ] || [ -z "$REGION" ] || [ -z "$NODE_ROLE_NAME" ]; then
  echo "STOP: terraform output 값 누락"
else
  mkdir -p rendered
  for f in *.yaml; do
    sed -e "s|\${ECR_IMAGE}|${ECR_IMAGE}|g" -e "s|\${QUEUE_URL}|${QUEUE_URL}|g" -e "s|\${REGION}|${REGION}|g" -e "s|\${NODE_ROLE_NAME}|${NODE_ROLE_NAME}|g" "$f" > "rendered/$f"
  done
  if grep -rn '\${' rendered/; then echo "STOP: 미치환 값 존재"
  else kubectl apply -f rendered/; fi   # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
fi
cd ..
```

큐가 비어 있으면 minReplicaCount 0이라 pod 0개가 정상이다 — scale-out 확인은 6단계에서 한다. apply 결과는 리소스 존재로만 확인:

```bash
kubectl get scaledobject,triggerauthentication -n skills-sqs
kubectl get nodepool,ec2nodeclass
```

## 6. 스케일 검증 (mark2-4.sh 4-6 시나리오 수동 재현)

```bash
for i in $(seq 1 12); do
  aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "verify-${i}" >/dev/null
done
for t in 60 120 180; do
  sleep 60
  echo "=== after ${t}s ==="
  aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table
  kubectl get deployment sqs-worker -n skills-sqs
  kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
  kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
done
```

`ApproximateNumberOfMessages=0` 확인 후 cooldownPeriod(30s)·consolidateAfter(30s) 경과 대기, pod 0·노드 0 복귀 확인:

```bash
sleep 90
kubectl get pods -n skills-sqs -l app=sqs-worker
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool
```

## 7. [CloudShell] kubectl 확인 (협의회 필수 요구)

[README.md](README.md) 7단계를 수행한다. `Unauthorized` 시에만 아래를 본 PC에서 실행:

```bash
aws eks create-access-entry --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region us-west-2
aws eks associate-access-policy --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> \
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region us-west-2
```

## 8. 채점 직전 사전 활성화 (선택 — 저비용 보험)

공식 예상 출력(`provided/008_chall_2nd_patched_0801.md` 4-5 판정 기준)이 4-5의 Worker Pod 배치를 4-6 출력 결과를 포함해 판정할 수 있다고 명시해 이 단계 없이도 감점되지 않는다. 비용이 사실상 0이라 보험으로 유지한다. mark2-4.sh는 [4-5](Karpenter NodePool·EC2NodeClass·배치)를 [4-6](스케일아웃 검증, 12건 발송)보다 먼저 조회한다. minReplicaCount 0 설계상 큐가 비어 있으면 pod·노드가 0개인 상태가 정상이지만, 그 상태로 채점을 시작하면 4-5 시점에 아무 것도 조회되지 않는다. **purge는 하지 않는다** — 메시지는 5초/건으로 처리되고 cooldown 후 자연히 0으로 복귀하며, 채점 자체가 4-6에서 12건을 새로 발송한다. 대신 채점 시작 직전에 메시지를 미리 보내 pod·노드를 활성 상태로 만들어 둔다:

```bash
for i in $(seq 1 6); do
  aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "pre-mark-${i}" >/dev/null
done
# 노드 프로비저닝 포함 최대 3분 대기, Running pod 확인되면 즉시 진행
for i in $(seq 1 18); do
  sleep 10
  running=$(kubectl get pods -n skills-sqs -l app=sqs-worker --field-selector=status.phase=Running --no-headers 2>/dev/null)
  [ -n "$running" ] && break
done
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
# 위 두 명령에서 pod가 Running(≥1)이고 Karpenter 노드가 조회되면 채점 시작
```

[CloudShell] 셀프 채점: [README.md](README.md) 8단계 CloudShell 항목을 수행한다.

```bash
# CloudShell 에서 mark/mark2-4.sh 를 git clone 또는 파일 업로드(Actions → Upload file)로 전송 후 실행.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark/mark2-4.sh
bash mark/mark2-4.sh
```

## 9. Teardown

```bash
cd k8s
kubectl delete -f rendered/
cd ..
helm uninstall keda -n keda
helm uninstall karpenter -n karpenter
cd eksctl
eksctl delete cluster -f rendered/cluster.yaml
cd ../terraform
terraform destroy -auto-approve
cd ..
```
