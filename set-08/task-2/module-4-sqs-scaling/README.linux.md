# 본 PC가 Linux일 때의 런북 (module-4-sqs-scaling)

[README.md](README.md)의 본 PC 단계를 bash/zsh 겸용으로 옮긴 것. 번호는 README.md와 1:1 대응이며, CloudShell 단계도 자리에 그대로 유지했다.

## 0. 시작 전 확인 (대회 시작 직후 1회)

**CloudShell 접속을 확인**한다. 이 모듈은 로컬에 Docker가 없어 이미지 build/push(3단계)가 CloudShell 필수 경로이므로, 접속이 안 되면 모듈 전체가 막힌다. 활성 탭이 이전 세션의 VPC 환경이면 기본 리전 탭으로 전환한다(그 상태에선 파일 업로드가 비활성이다).

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
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -json > outputs.json   # 커밋 금지 (.gitignore)
```

주요 output을 세션 변수로 로드하고 `.env`(본 PC 재접속·CloudShell 업로드 겸용)로 저장한다:

```bash
export ACCOUNT_ID=$(terraform -chdir=terraform output -raw account_id)
export REGION=us-west-2
export VPC_ID=$(terraform -chdir=terraform output -raw vpc_id)
export PRIV_SUBNET_A=$(terraform -chdir=terraform output -json private_subnet_ids | jq -r '.["skills-sqs-sn-priv-a"]')
export PRIV_SUBNET_B=$(terraform -chdir=terraform output -json private_subnet_ids | jq -r '.["skills-sqs-sn-priv-b"]')
export QUEUE_URL=$(terraform -chdir=terraform output -raw queue_url)
ECR_REPO_URL=$(terraform -chdir=terraform output -raw ecr_repo_url)
# 중괄호 필수: zsh 는 "$ECR_REPO_URL:latest" 의 :l 을 소문자 modifier 로 해석해 이미지명이 깨진다
export ECR_IMAGE="${ECR_REPO_URL}:latest"
export KEDA_POLICY_ARN=$(terraform -chdir=terraform output -raw keda_policy_arn)
export KARPENTER_POLICY_ARN=$(terraform -chdir=terraform output -raw karpenter_policy_arn)
export WORKER_POLICY_ARN=$(terraform -chdir=terraform output -raw worker_policy_arn)
export NODE_ROLE_ARN=$(terraform -chdir=terraform output -raw karpenter_node_role_arn)
export NODE_ROLE_NAME=$(terraform -chdir=terraform output -raw karpenter_node_role_name)

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

렌더와 실행을 붙이지 않는다. 2-1 환경 변수 검토 → 2-2 렌더 → 2-3 렌더 결과 값 검토 → 2-4 실행 순으로 끊어서, 잘못된 값이 20분짜리 `eksctl create` 에 들어가기 전에 눈으로 잡는다.

### 2-1. 환경 변수 검토

```bash
# printf 는 인자가 남으면 포맷을 반복 적용한다 — 이름/값 쌍을 그대로 나열
printf '%-22s = %s\n' \
  VPC_ID "$VPC_ID" \
  PRIV_SUBNET_A "$PRIV_SUBNET_A" \
  PRIV_SUBNET_B "$PRIV_SUBNET_B" \
  KEDA_POLICY_ARN "$KEDA_POLICY_ARN" \
  KARPENTER_POLICY_ARN "$KARPENTER_POLICY_ARN" \
  WORKER_POLICY_ARN "$WORKER_POLICY_ARN" \
  NODE_ROLE_ARN "$NODE_ROLE_ARN"
```

- 빈 값이 하나라도 있으면 여기서 멈추고 1단계의 `source .env` 부터 다시 한다 (`envsubst` 는 unset 변수를 빈 문자열로 조용히 치환하므로 렌더 후에는 안 잡힌다).
- `VPC_ID` 는 `vpc-`, 서브넷 2개는 `subnet-` 으로 시작하고 서로 달라야 한다.
- ARN 4개는 `arn:aws:iam::<ACCOUNT_ID>:` 로 시작하고 계정번호가 `$ACCOUNT_ID` 와 같아야 한다. `NODE_ROLE_ARN` 만 `:role/`, 나머지 3개는 `:policy/` 다.

### 2-2. 렌더

```bash
mkdir -p eksctl/rendered
# 변수 목록 명시 → 목록 외 신규 플레이스홀더는 치환되지 않고 남아 2-3 grep 에 걸린다
envsubst '${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_B} ${KEDA_POLICY_ARN} ${KARPENTER_POLICY_ARN} ${WORKER_POLICY_ARN} ${NODE_ROLE_ARN}' < eksctl/cluster.yaml > eksctl/rendered/cluster.yaml
```

### 2-3. 렌더 결과 값 검토

```bash
grep -n '\${' eksctl/rendered/cluster.yaml            # 출력 없어야 정상 (미치환 잔여)
grep -nE 'vpc-|subnet-|arn:aws:' eksctl/rendered/cluster.yaml
```

치환된 줄만 뽑힌다. `id:` 2줄(서브넷 a/b)이 서로 다른지, `principalARN` 이 role ARN 인지, `attachPolicyARNs` 3개가 keda/karpenter/worker 순서에 맞게 들어갔는지 확인한다. 첫 명령에 한 줄이라도 잡히면 실행하지 않는다.

### 2-4. eksctl create

```bash
eksctl create cluster -f eksctl/rendered/cluster.yaml
```

### 2-5. 완료 확인

`eksctl create`가 `$KUBECONFIG`(모듈 경로)에 컨텍스트를 자동 기록하므로 별도 `aws eks update-kubeconfig`는 불필요하다 — 아래로 클러스터 생성과 컨텍스트 연결을 함께 확인한다:

```bash
kubectl config current-context   # 모듈 kubeconfig 파일 경로가 그대로 나오면 연결 확인
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate
```

Fargate Node 2개(keda/karpenter용)가 나오면 4단계로 진행한다.

## 3. [CloudShell — 2단계 eksctl 생성 대기 중 병렬] worker 이미지 build/push

zip 묶기만 bash 로 (README.md 3단계의 `Compress-Archive` 대체), 이후 업로드·빌드는 [README.md](README.md) 3단계와 동일:

```bash
zip -j m4.zip app/Dockerfile ../provided/module-4/worker.py .env
```

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

2단계와 같이 4단계로 끊는다.

### 5-1. 환경 변수 검토

```bash
printf '%-16s = %s\n' \
  ECR_IMAGE "$ECR_IMAGE" \
  QUEUE_URL "$QUEUE_URL" \
  REGION "$REGION" \
  NODE_ROLE_NAME "$NODE_ROLE_NAME"
```

- 빈 값이 있으면 1단계의 `source .env` 부터 다시 한다.
- `ECR_IMAGE` 는 `<ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-worker:latest` 형태여야 한다(3단계에서 push 한 태그와 정확히 같아야 pull 된다 — zsh 의 `:l` modifier 로 소문자화돼 깨지지 않았는지 여기서 확인).
- `QUEUE_URL` 은 `https://sqs.us-west-2.amazonaws.com/<ACCOUNT_ID>/skills-sqs-queue`, `NODE_ROLE_NAME` 은 ARN 이 아니라 **역할 이름만** 이다.

### 5-2. 렌더

```bash
mkdir -p k8s/rendered
for f in k8s/*.yaml; do
  sed -e "s|\${ECR_IMAGE}|${ECR_IMAGE}|g" -e "s|\${QUEUE_URL}|${QUEUE_URL}|g" -e "s|\${REGION}|${REGION}|g" -e "s|\${NODE_ROLE_NAME}|${NODE_ROLE_NAME}|g" "$f" > "k8s/rendered/$(basename "$f")"
done
```

### 5-3. 렌더 결과 값 검토

```bash
grep -rn '\${' k8s/rendered/                                   # 출력 없어야 정상 (미치환 잔여)
grep -nE 'image:|queueURL|awsRegion|role:|value:' k8s/rendered/*.yaml
kubectl apply --dry-run=server -f k8s/rendered/                # 클러스터 스키마 검증 (실제 적용 없음)
```

`image:` 가 3단계에서 push 한 태그와 같은지, ScaledObject 의 `queueURL`·Deployment 의 `value:` 2줄(SQS_QUEUE_URL·AWS_REGION)이 6단계 검증에 쓸 큐·리전과 같은지, `role:` 이 Karpenter 노드 역할 **이름**인지 확인한다. 미치환이 잡히거나 dry-run 이 실패하면 실행하지 않는다.

### 5-4. apply

```bash
kubectl apply -f k8s/rendered/   # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
```

`namespace/skills-sqs`에 `missing the kubectl.kubernetes.io/last-applied-configuration annotation` 경고가 뜨는 건 정상이다 — eksctl Fargate profile이 네임스페이스를 먼저 만들어서 나며, 자동 패치된다.

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
  aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
  kubectl get deployment sqs-worker -n skills-sqs
  kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
  kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
  kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
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
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region us-west-2
```

## 8. 채점 직전 경량 상태 확인

4-5 감점 우려는 공식 예상 출력(`provided/008_chall_2nd_patched_0801.md` 4-5 판정 기준)이 4-5의 Worker Pod 배치를 4-6 출력 결과를 포함해 판정할 수 있다고 명시해 해소됐다. 스케일아웃 파이프라인 실동작 검증은 6단계에서 이미 마쳤으므로(12건 발송, 소진·복귀까지 확인) 채점 직전에 SQS 메시지를 다시 보낼 필요는 없다 — 6단계 이후 상태 변경 없이 그대로인지만 가볍게 확인한다:

```bash
kubectl get pods -n keda
kubectl get pods -n karpenter
kubectl get scaledobject,triggerauthentication -n skills-sqs
kubectl get nodepool,ec2nodeclass
# 컨트롤러 pod Running, ScaledObject/TriggerAuthentication/NodePool/EC2NodeClass 존재 확인되면 채점 시작
```

[CloudShell] 셀프 채점: [README.md](README.md) 8단계 CloudShell 항목을 수행한다.

```bash
# mark/mark2-4.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark2-4.sh
bash mark2-4.sh
```

`mark2-4.sh`는 kubectl 설치 + 4-6의 `sleep 60`×3 때문에 실측 **약 11분** 걸린다(다른 모듈 채점은 각 1~3분).

## 9. Teardown

```bash
kubectl delete -f k8s/rendered/ --wait=false
helm uninstall keda -n keda
helm uninstall karpenter -n karpenter
eksctl delete cluster -f eksctl/rendered/cluster.yaml
terraform -chdir=terraform destroy -auto-approve
```

- `--wait=false`를 쓰는 이유: 기본 동작이면 삭제 메시지를 다 출력한 뒤에도 kubectl이 종료되지 않고 매달려(실측 15분+) 뒤의 `helm uninstall`이 실행되지 않는다.
- 매달린 kubectl을 끊고 진행해도 된다. 이때 `helm uninstall`이 `Failed to purge the release: ... not found` 경고를 내도 리소스는 제거된 상태다.
- `eksctl delete cluster`는 실측 약 8분(Fargate profile 3개, 프로필당 ~2분).
