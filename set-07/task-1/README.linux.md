# 본 PC 가 Linux 일 때의 런북 (set-07 / task-1)

[README.md](README.md) 의 **본 PC 단계(0·1·3·6·8 + 정리 T2~T6)** 를 bash 로 옮긴 것.
CloudShell 단계(2·4·5·7·T1)는 실제 호스트가 리눅스라 README.md 와 동일하다.
리소스·순서·검증은 전부 같고 명령 문법만 다르다.

### 0) [본 PC] 사전 변수 · 신원 확인

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<선수등번호>     # ExternalId / Grafana 계정에 사용

# 본 PC 신원 = 채점 CloudShell 신원(지급 IAM 사용자)이어야 한다
aws sts get-caller-identity --query Arn --output text
```

> 본 PC 가 클러스터를 만들므로(step 3) `bootstrapClusterCreatorAdminPermissions: true` 에 따라
> 본 PC 신원이 그대로 클러스터 admin 이 된다. 어긋나도 README.md step 4 각주의 access entry 로 보정된다.

### 1) [본 PC] Terraform (네트워크 + AWS 리소스)

```bash
cd terraform
terraform init
terraform apply -var="player_number=$NUM"
terraform output -json > ../outputs.json   # 본 PC 안에서만 쓴다 (step 3 eksctl · 아래 .env 블록)

export ACCOUNT_ID=$(jq -r '.account_id.value' ../outputs.json)
export BUCKET=$(jq -r '.s3_bucket_name.value' ../outputs.json)

# 재접속 대비 (작업 규칙 6, .gitignore 등록됨). 새 셸에선 task-1 에서 `source .env` 만 다시 실행
cat > ../.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$ACCOUNT_ID
export BUCKET=$BUCKET
EOF

# CloudShell 은 파일 업로드 UI 가 없고(VPC environment 는 Actions 업로드 자체가 막혀 있다)
# 레포가 비공개라 git clone 도 불가 → 붙여넣을 수 없는 것만 S3 릴레이로 넘긴다.
# _transfer/ 는 채점 직전 step 8 에서 비운다 (web 버킷은 채점 대상 — mark.sh 3-1-A).
tar czf ../task.tgz -C .. k8s mark-2026-08-10.sh   # 2026-08-10 정정본. mark.sh 최초본은 대조용
aws s3 cp ../task.tgz "s3://$BUCKET/_transfer/task.tgz"
aws s3 cp ../../../shared/provided/task-1/book "s3://$BUCKET/_transfer/book"   # 8.7MB 바이너리
```

**step 4 에 붙여넣을 `.env` 블록 출력** — 텍스트는 S3 를 태우지 않는다.

```bash
# 따옴표 없는 heredoc → $(...) 가 지금 평가되어 값이 정적으로 박힌다.
# 그래서 CloudShell 에 outputs.json 도 jq 도 필요 없다.
cat <<EOF
cat > ~/.env <<'ENVEOF'
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$(jq -r '.account_id.value' ../outputs.json)
export VPC_ID=$(jq -r '.vpc_id.value' ../outputs.json)
export PLATFORM_KMS_ARN=$(jq -r '.platform_kms_arn.value' ../outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' ../outputs.json)
export APP_TG=$(jq -r '.app_target_group_arn.value' ../outputs.json)
export GRAFANA_TG=$(jq -r '.grafana_target_group_arn.value' ../outputs.json)
export GRAFANA_USER=skills$NUM
export GRAFANA_PW='HelloKrSkills!'$NUM'@'
ENVEOF
sed -i 's/\\r\$//' ~/.env
EOF
```

> 출력된 블록을 그대로 step 4 에 붙여넣는다. 우변이 빈 줄(`export VPC_ID=`)이 있으면 outputs.json 이
> 덜 만들어진 것이니 `terraform apply` 부터 다시 본다.
> 마지막 `sed` 는 CRLF 가드다 — Linux 본 PC 에선 안 생기지만 README.md 와 블록을 같게 유지한다. 멱등하다.
> 세션이 끊겨 블록을 잃으면 이 블록만 다시 실행하면 된다(작업 규칙 6).

> `eksctl/` 은 릴레이에 넣지 않는다 — 본 PC 에서만 쓴다.

### 2) → README.md step 2 (일반 CloudShell — 이미지 빌드/푸시)

로컬에 Docker 가 있어도 CloudShell 에서 하는 편이 낫다 — ECR 로그인·푸시 경로가 채점 계정과 같고,
`--platform` 을 신경 쓸 필요가 없다. `book` 만 S3 에서 받고 `Dockerfile` 은 heredoc 으로 붙여넣는다.

### 3) [본 PC] EKS 클러스터 (eksctl)

```bash
cd ../eksctl     # cwd = terraform 이었을 때
source ../.env   # 새 셸이면

export VPC_ID=$(jq -r '.vpc_id.value' ../outputs.json)
export CP_EXTRA_SG_ID=$(jq -r '.eks_cp_extra_sg_id.value' ../outputs.json)
export NODE_SHARED_SG_ID=$(jq -r '.eks_shared_node_sg_id.value' ../outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-a"]' ../outputs.json)
export PRIV_SUBNET_B=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-b"]' ../outputs.json)
export PRIV_SUBNET_C=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-c"]' ../outputs.json)
export PLATFORM_KMS_ARN=$(jq -r '.platform_kms_arn.value' ../outputs.json)
export BOOK_APP_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.book_app' ../outputs.json)
export LBC_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.lbc' ../outputs.json)
export FLUENTBIT_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.fluentbit' ../outputs.json)
export CWEXPORTER_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.cwexporter' ../outputs.json)
export EBS_CSI_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.ebs_csi' ../outputs.json)
export CF=$(jq -r '.cloudfront_domain.value' ../outputs.json)   # step 6 시드용

rm -f cluster.rendered.yaml   # 이전 실행 잔재로 검사를 통과하는 일이 없게

# 치환 전: cluster.yaml 이 요구하는 env 가 다 있는지 검사
missing=$(for v in $(grep -oh '[$]{[A-Za-z_][A-Za-z_0-9]*}' cluster.yaml | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)

if [ -n "$missing" ]; then
  echo "env 누락: $missing — 위 export 블록을 다시 실행"
else
  # envsubst(gettext) 미설치 대비 python3 — 미선언 변수를 빈 값으로 지우지 않고 ${VAR} 그대로 남긴다
  python3 -c 'import os,sys;sys.stdout.write(os.path.expandvars(sys.stdin.read()))' \
    < cluster.yaml > cluster.rendered.yaml
  grep -n '\${' cluster.rendered.yaml && echo '치환 누락!' || echo OK
fi

# 셸 재시작 대비 — .env 재작성 (작업 규칙 6)
cat > ../.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$ACCOUNT_ID
export BUCKET=$BUCKET
export CF=$CF
EOF

# 위에서 OK 가 나왔을 때만 진행
eksctl create cluster -f cluster.rendered.yaml     # 약 20분. 완료 시 자동 private 전환

# 엔드포인트 확인 — 건너뛰지 않는다 (채점 6-1-A)
aws eks describe-cluster --name unicorn-eks-cluster \
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true

# true 로 남았으면 (eksctl 이 중간에 끊긴 경우):
# aws eks update-cluster-config --name unicorn-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

### 4~5) → README.md step 4~5 (`unicorn-mark` CloudShell — 부트스트랩 · helm · kubectl)

`unicorn-mark` VPC environment 를 만들고 helm 설치 → S3 에서 `task.tgz` 수신 →
**step 1 이 출력한 `.env` 블록 붙여넣기** → `source ~/.env` → `kubectl get nodes`,
이어서 helm 애드온 3개 + `kubectl apply -R -f rendered/`. README.md 와 동일한 bash 다.

### 6) [본 PC] 데이터/트래픽 시드

```bash
source ../.env   # 새 셸이면 (task-1 에서 source .env)

curl -s -X POST "https://$CF/v1/book" -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Seoul2025"}'   # booking_id 반환
for i in $(seq 1 20); do curl -s -o /dev/null "https://$CF/health"; done                              # ALB 메트릭 생성
```

### 7) → README.md step 7 (`unicorn-mark` CloudShell — 자가 채점)

`bash ~/mark-2026-08-10.sh`. 홈이 초기화된 뒤라면 step 4 부트스트랩 블록을 먼저 다시 실행한다.

### 8) [본 PC] 채점 전 정리

자가 채점을 통과한 뒤 **채점 직전**에 실행한다. `_transfer/` 를 지우면 step 4 부트스트랩 재료가
사라지므로 순서를 앞당기지 않는다.

```bash
source ../.env   # 새 셸이면 (task-1 에서 source .env)

# S3 릴레이 제거 (web 버킷은 채점 대상 — mark.sh 3-1-A)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix _transfer/ --query 'Contents[].Key'  # null 확인
```

---

## 리소스 정리 (teardown)

막히는 지점과 순서 근거는 [README.md 의 정리 섹션](README.md#리소스-정리-teardown) 표를 본다. 여기는 본 PC 단계의 bash 판이다.

### T1) → README.md T1 (`unicorn-mark` CloudShell — PVC 회수)

클러스터가 살아있을 때 `helm uninstall` + `kubectl delete pvc` 로 EBS 를 먼저 회수한다. 건너뛰면 T6 에서 `available` 볼륨을 직접 지운다.

### T2) [본 PC] EKS 클러스터

```bash
eksctl delete cluster -f eksctl/cluster.rendered.yaml --disable-nodegroup-eviction --force --wait
```

### T3) [본 PC] DynamoDB 삭제 보호 해제

```bash
aws dynamodb update-table --table-name unicorn-concert-db --no-deletion-protection-enabled
aws dynamodb describe-table --table-name unicorn-concert-db   --query 'Table.[TableStatus,DeletionProtectionEnabled]' --output text   # ACTIVE False 확인
```

### T4) [본 PC] S3 버킷 비우기 (버전 + 삭제마커)

```bash
source .env   # 새 셸이면 (task-1 에서). 없으면 아래 한 줄로 대체
# BUCKET="unicorn-web-$(aws sts get-caller-identity --query Account --output text)"

# 버전 + 삭제마커를 delete-objects 페이로드 모양 그대로 뽑아 파일로 넘긴다
while :; do
  aws s3api list-object-versions --bucket "$BUCKET" --max-items 500 --output json     --query '{Objects: [Versions, DeleteMarkers][].{Key:Key,VersionId:VersionId}}' > /tmp/del.json
  grep -q '"Objects": null' /tmp/del.json && break
  aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/del.json >/dev/null
done
aws s3api list-object-versions --bucket "$BUCKET" --output json   # {} 이어야 한다
```

### T5) [본 PC] terraform destroy

```bash
terraform -chdir=terraform destroy
```

### T6) [본 PC] 잔재 확인

```bash
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size]' --output text
aws ec2 describe-vpcs --query "Vpcs[?Tags[?Key=='Name'&&Value=='unicorn-vpc']].VpcId" --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'unicorn')].RoleName" --output text
aws logs describe-log-groups --query "logGroups[?contains(logGroupName,'unicorn')].logGroupName" --output text
aws cloudfront list-vpc-origins --query 'VpcOriginList.Items[].Name' --output text
aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'unicorn')].LoadBalancerName" --output text
aws s3api list-buckets --query "Buckets[?starts_with(Name,'unicorn')].Name" --output text
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED   --query "StackSummaries[?contains(StackName,'unicorn')].[StackName,StackStatus]" --output text
```
