# 본 PC 가 Linux 일 때의 런북 (set-06 / task-1)

[README.md](README.md) 의 **본 PC 단계(0~8 + 정리 T1~T5)** 를 bash 로 옮긴 것.
채점 단계(9)는 실제 호스트가 리눅스라 README.md 와 동일하다.
리소스·순서·검증·주의는 전부 같고 명령 문법만 다르다 — **왜 이 순서인지는 README.md 를 본다.**

### 0) [본 PC] 사전 변수 · 신원 확인

```bash
cd set-06/task-1/terraform
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<선수등번호>          # bibunho — S3 버킷 이름에 들어간다

aws sts get-caller-identity --query Arn --output text
```

### 1) [본 PC] ECR 선행 생성

```bash
terraform init
terraform apply -var "bibunho=$NUM" \
  -target=aws_ecr_repository.book -target=aws_ecr_repository.direct \
  -target=aws_ecr_pull_through_cache_rule.public

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR="$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
```

### 2) [본 PC] book 이미지 빌드·push (채점 2-2 의 3MB 제한)

```bash
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR"

docker buildx build --platform linux/amd64 --provenance=false \
  --output "type=image,name=$ECR/book:latest,oci-mediatypes=true,compression=zstd,compression-level=19,force-compression=true,push=true" \
  -f ../app/Dockerfile ../../../shared/provided/set-06-task-1

# 3145728(3MB) 이하여야 한다
aws ecr describe-images --repository-name book \
  --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text
```

### 3) [본 PC] 나머지 AWS 리소스 (CloudFront 포함 — 최대 15분)

```bash
terraform apply -var "bibunho=$NUM"
terraform output -json > outputs.json

export VPC_ID=$(jq -r .vpc_id.value outputs.json)
export SUBNET_A_ID=$(jq -r '.private_subnet_ids.value[0]' outputs.json)
export SUBNET_B_ID=$(jq -r '.private_subnet_ids.value[1]' outputs.json)
export EKS_KMS_ARN=$(jq -r .eks_kms_arn.value outputs.json)
export NODE_SHARED_SG_ID=$(jq -r .node_shared_sg_id.value outputs.json)
export BOOK_POD_SG_ID=$(jq -r .book_pod_sg_id.value outputs.json)
export BOOK_TG_ARN=$(jq -r .book_tg_arn.value outputs.json)
export GRAFANA_TG_ARN=$(jq -r .grafana_tg_arn.value outputs.json)
export BOOK_APP_POLICY_ARN=$(jq -r .book_app_policy_arn.value outputs.json)
export GRAFANA_POLICY_ARN=$(jq -r .grafana_policy_arn.value outputs.json)
export FLUENTBIT_POLICY_ARN=$(jq -r .fluentbit_policy_arn.value outputs.json)
export LBC_POLICY_ARN=$(jq -r .lbc_policy_arn.value outputs.json)
export NODE_PTC_POLICY_ARN=$(jq -r .node_ptc_policy_arn.value outputs.json)
export CF_DOMAIN=$(jq -r .cloudfront_domain.value outputs.json)
export CF_DIST_ID=$(jq -r .cloudfront_distribution_id.value outputs.json)
```

**`.env` 재작성** — 손으로 나열하지 않고 키 목록에서 통째로 다시 쓴다(작업 규칙 6, `.gitignore` 등록됨).

```bash
KEEP="AWS_REGION AWS_DEFAULT_REGION NUM ACCOUNT_ID ECR VPC_ID SUBNET_A_ID SUBNET_B_ID \
EKS_KMS_ARN NODE_SHARED_SG_ID BOOK_POD_SG_ID BOOK_TG_ARN GRAFANA_TG_ARN \
BOOK_APP_POLICY_ARN GRAFANA_POLICY_ARN FLUENTBIT_POLICY_ARN LBC_POLICY_ARN \
NODE_PTC_POLICY_ARN CF_DOMAIN CF_DIST_ID"

missing=$(for v in $KEEP; do [ -z "${!v}" ] && echo "$v"; done)
[ -n "$missing" ] && { echo "env 누락: $missing — 위 블록을 다시 실행"; false; }

: > ../.env
for v in $KEEP; do echo "export $v='${!v}'" >> ../.env; done
source ../.env      # 새 셸로 이어서 할 땐 task-1 에서 `source .env` 만 다시 실행
```

### 4) [본 PC] 보조 이미지 push + PTC 워밍업

```bash
docker pull public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.4
docker tag  public.ecr.aws/bottlerocket/bottlerocket-bootstrap:v0.3.4 "$ECR/gj2026/br-bootstrap:1.0.0"
docker push "$ECR/gj2026/br-bootstrap:1.0.0"

docker pull grafana/grafana:13.1.0
docker tag  grafana/grafana:13.1.0 "$ECR/mirror/grafana:13.1.0"
docker push "$ECR/mirror/grafana:13.1.0"
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1
docker tag  public.ecr.aws/eks/aws-load-balancer-controller:v2.17.1 "$ECR/mirror/aws-load-balancer-controller:v2.17.1"
docker push "$ECR/mirror/aws-load-balancer-controller:v2.17.1"

docker pull "$ECR/ecr-public/nginx/nginx:latest"
docker pull "$ECR/ecr-public/aws-observability/aws-for-fluent-bit:3.4.8"

# 리포지토리만 있고 태그가 없으면 노드가 조용히 부팅에 실패한다
aws ecr describe-images --repository-name gj2026/br-bootstrap --query 'imageDetails[].imageTags' --output text
```

### 5) [본 PC] EKS 클러스터 + 인증 전환 + scale-up

> **노드 0대 생성 → 인증 전환 → scale-up** 순서를 반드시 지킨다. 이유는 README.md 5단계.

```bash
cd ../eksctl
source ../.env

# bootstrap 스크립트 → base64 (CR 제거 필수 — Bottlerocket 에서 실행 실패 방지)
export SET_HOSTNAME_ADDON_B64=$(tr -d '\r' < bootstrap/set-hostname-addon.sh | base64 -w0)
export SET_HOSTNAME_APP_B64=$(tr -d '\r' < bootstrap/set-hostname-app.sh | base64 -w0)

rm -f cluster.rendered.yaml     # 이전 잔재로 검사를 통과하는 일이 없게

# 치환 전: cluster.yaml 이 요구하는 env 가 전부 있는지 검사
missing=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' cluster.yaml | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)
if [ -n "$missing" ]; then
  echo "env 누락: $missing — 3단계 .env 를 다시 source"
else
  python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' \
    < cluster.yaml > cluster.rendered.yaml
  grep -n '\${' cluster.rendered.yaml && echo '치환 누락!' || echo OK
fi

# 위에서 OK 가 나왔을 때만 진행
eksctl create cluster -f cluster.rendered.yaml --cfn-disable-rollback   # 약 15~20분

aws eks update-kubeconfig --name gj2026-eks-cluster
kubectl get nodes    # 아직 0개 (desired 0) — 정상
```

```bash
addonRole=$(aws eks describe-nodegroup --cluster-name gj2026-eks-cluster --nodegroup-name gj2026-eks-addon-nodegroup --query nodegroup.nodeRole --output text)
appRole=$(aws eks describe-nodegroup --cluster-name gj2026-eks-cluster --nodegroup-name gj2026-eks-app-nodegroup --query nodegroup.nodeRole --output text)

# 1) 자동 생성된 EC2_LINUX access entry 삭제
aws eks delete-access-entry --cluster-name gj2026-eks-cluster --principal-arn "$addonRole"
aws eks delete-access-entry --cluster-name gj2026-eks-cluster --principal-arn "$appRole"

# 2) eksctl 기본 매핑 제거
eksctl delete iamidentitymapping --cluster gj2026-eks-cluster --arn "$addonRole" --all
eksctl delete iamidentitymapping --cluster gj2026-eks-cluster --arn "$appRole" --all

# 3) aws-auth 매핑 — {{SessionName}} = instance-id
eksctl create iamidentitymapping --cluster gj2026-eks-cluster --arn "$addonRole" \
  --username 'system:node:gj2026.{{SessionName}}.addon.node' --group system:bootstrappers --group system:nodes
eksctl create iamidentitymapping --cluster gj2026-eks-cluster --arn "$appRole" \
  --username 'system:node:gj2026.{{SessionName}}.app.node' --group system:bootstrappers --group system:nodes

# 4) scale-up (채점 4-2: desired 2)
eksctl scale nodegroup --cluster gj2026-eks-cluster --name gj2026-eks-addon-nodegroup --nodes 2 --nodes-min 2
eksctl scale nodegroup --cluster gj2026-eks-cluster --name gj2026-eks-app-nodegroup   --nodes 2 --nodes-min 2

kubectl get nodes    # 2~5분 내 4개 Ready

# 채점 4-3 사전 검증 (mark.sh 와 같은 로직 — 4개가 전부 출력돼야 한다)
kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers |
  awk -F. '$2 ~ /^i-/ {print}'

# 5) kubelet-serving CSR 수동 승인 (필수)
kubectl get csr -o name | xargs -r -n1 kubectl certificate approve
kubectl top nodes    # 1분 내 4개 노드 메트릭이 나오면 정상
```

### 6) [본 PC] Helm 애드온 + Kubernetes 리소스

```bash
cd ../k8s
source ../.env

kubectl set env daemonset aws-node -n kube-system ENABLE_POD_ENI=true    # Pod 생성 전에 건다
kubectl apply -f 00-namespace.yaml

render() {   # $1 = src, $2 = dst. 미설정 env 는 빈 문자열로 삼키지 않고 멈춘다
  local miss; miss=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' "$1" | tr -d '${}' | sort -u); do
    [ -z "${!v}" ] && echo "$v"; done)
  [ -n "$miss" ] && { echo "env 누락($1): $miss"; return 1; }
  mkdir -p "$(dirname "$2")"
  python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' < "$1" > "$2"
}

# 6-1) LBC — TargetGroupBinding CRD 제공이라 TGB 보다 먼저
helm repo add eks https://aws.github.io/eks-charts && helm repo update
render lbc-values.yaml lbc-values.rendered.yaml
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f lbc-values.rendered.yaml

# 6-2) Grafana — release 이름을 정확히 `grafana` 로 고정 (TGB serviceRef 와 일치)
helm repo add grafana-community https://grafana-community.github.io/helm-charts && helm repo update
render monitoring/grafana-values.yaml monitoring/grafana-values.rendered.yaml
helm upgrade --install grafana grafana-community/grafana -n monitoring -f monitoring/grafana-values.rendered.yaml

# 6-3) Fluent Bit — release 이름 = DaemonSet 이름 (채점이 rollout restart 를 건다)
render logging/fluent-bit-values.yaml logging/fluent-bit-values.rendered.yaml
helm upgrade --install aws-for-fluent-bit eks/aws-for-fluent-bit -n logging -f logging/fluent-bit-values.rendered.yaml
```

```bash
rm -rf rendered

# helm values 와 그 렌더 결과는 kubectl 대상이 아니므로 제외
srcs=$(find . -path ./rendered -prune -o -name '*.yaml' ! -name '*-values*.yaml' -print)
for f in $srcs; do render "$f" "rendered/$f" || break; done

grep -rn '\${' rendered/ && echo '치환 누락!' || echo OK

kubectl apply -R -f rendered/
aws elbv2 wait target-in-service --target-group-arn "$BOOK_TG_ARN"
```

### 7) [본 PC] 데이터/트래픽 시드

```bash
source ../.env
CF="https://$CF_DOMAIN"

curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" "$CF"
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" "$CF/index.html"
curl -sX POST -H "Content-Type: application/json" \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Busan2025"}' "$CF/v1/book"
curl -s "$CF/reservation?client_id=C001"
curl -s -w " %{http_code}\n" "$CF/v1/book"                        # 405
curl -s -w " %{http_code}\n" "$CF/reservation?client_id=123abc"   # 403
```

### 8) [본 PC] 채점 전 정리

> `books` 테이블은 채점 시작 시점에 **반드시 0건**이어야 한다. 이유는 README.md 8단계.

```bash
cd ../terraform
terraform apply -var "bibunho=$NUM" -var enable_ddb_write_deny=false

aws dynamodb scan --table-name books --projection-expression booking_id \
  --query 'Items[].booking_id.S' --output text | tr '\t' '\n' | while read -r id; do
    [ -n "$id" ] && aws dynamodb delete-item --table-name books --key "{\"booking_id\":{\"S\":\"$id\"}}"
  done

terraform apply -var "bibunho=$NUM" -var enable_ddb_write_deny=true

# ★ Deny 전파 확인 (필수) — 전파 전에 채점하면 3-3 이 깨지고 8-3 까지 오염된다
while :; do
  if aws dynamodb put-item --table-name books \
       --item '{"booking_id":{"S":"deny-probe"},"client_id":{"S":"X"}}' 2>&1 | grep -q AccessDenied; then
    echo "Deny 활성 확인 — 채점 시작 가능"; break
  fi
  aws dynamodb delete-item --table-name books --key '{"booking_id":{"S":"deny-probe"}}' 2>/dev/null
  sleep 10
done

aws cloudfront create-invalidation --distribution-id "$CF_DIST_ID" --paths '/*'
echo "$CF_DIST_ID"     # 9단계 CloudShell 에 붙여넣을 값
```

### 9) → README.md 9단계 (채점 CloudShell — 자가 채점)

호스트가 리눅스라 명령이 같다. README.md 9단계를 그대로 쓴다.

## 리소스 정리 (teardown)

막는 지점과 순서의 근거는 README.md 「리소스 정리」 표를 본다.

### T1) [본 PC] DynamoDB 비우기

```bash
cd set-06/task-1/terraform && source ../.env
terraform apply -var "bibunho=$NUM" -var enable_ddb_write_deny=false
# 8단계의 scan → delete-item 루프를 그대로 다시 돌린다
```

### T2) [본 PC] ECR 이미지 삭제

```bash
for r in book gj2026/br-bootstrap mirror/grafana mirror/aws-load-balancer-controller; do
  ids=$(aws ecr list-images --repository-name "$r" --query 'imageIds[*]' --output json)
  [ "$ids" != "[]" ] && aws ecr batch-delete-image --repository-name "$r" --image-ids "$ids" >/dev/null
done
```

### T3) [본 PC] EKS 클러스터

```bash
eksctl delete cluster -f ../eksctl/cluster.rendered.yaml --disable-nodegroup-eviction --wait
```

### T4) [본 PC] terraform destroy

```bash
terraform destroy -var "bibunho=$NUM"
```

### T5) [본 PC] 잔재 확인

```bash
# 계정에 다른 세트 리소스가 섞여 있다. 반드시 이름·태그로 좁힌다
aws ec2 describe-vpcs --query "Vpcs[?Tags[?Key=='Name'&&Value=='gj2026-vpc']].VpcId" --output text
aws ec2 describe-volumes --filters "Name=tag-key,Values=kubernetes.io/cluster/gj2026-eks-cluster" \
  --query "Volumes[].[VolumeId,State,Size]" --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'gj2026')].RoleName" --output text
aws logs describe-log-groups --query "logGroups[?contains(logGroupName,'gj2026')||contains(logGroupName,'book-svc')].logGroupName" --output text
aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'gj2026')].LoadBalancerName" --output text
aws s3api list-buckets --query "Buckets[?starts_with(Name,'gj2026')].Name" --output text
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED \
  --query "StackSummaries[?contains(StackName,'gj2026')].[StackName,StackStatus]" --output text
```
