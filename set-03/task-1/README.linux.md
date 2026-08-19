# 본 PC 가 Linux 일 때의 런북 (set-03 / task-1)

[README.md](README.md) 의 본 PC 단계(0·1·3·7·9·10)를 bash 로 옮긴 것.
원격 단계(2 일반 CloudShell · 4·5·6·8 bastion · 9-2 VPC CloudShell)는 README.md 와 동일.
주의/함정·설계 이력은 [NOTES.md](NOTES.md).

### 0) [본 PC] 도구 준비 + 콘솔 자격증명 로그인 + 사전 변수

필요 도구: AWS CLI v2 **2.32.0 이상**(`aws login` 요건) · Terraform · eksctl · jq ·
gettext(envsubst) · session-manager-plugin(bastion SSM 접속) (Docker 불필요).

> **모든 단계를 지급받은 root 로 수행한다.** 채점도 root 콘솔 세션으로 진행되므로 클러스터 생성자·
> KMS·S3 신원이 채점 셸과 어긋나지 않는다. 액세스 키는 만들지 않는다.

```bash
aws --version                          # 2.32.0 이상

# 브라우저에서 root 로 콘솔에 로그인해 둔 상태에서 실행 (default 프로파일)
aws login              # region = ap-northeast-2

# local .env (작업 규칙 6, .gitignore 등록됨)
cat > .env <<'EOF'
export AWS_DEFAULT_REGION=ap-northeast-2
EOF
source .env
aws sts get-caller-identity --query Arn --output text   # arn:aws:iam::<계정ID>:root 확인
# root 가 아니면 ~/.aws/credentials 의 잔존 키가 login 크레덴셜을 이긴 것 — 그 파일을 지운다
# 세션은 최대 12시간(15분마다 자동 갱신). ExpiredToken 이 뜨면 aws login 재실행

# terraform·eksctl 이 login 자격증명을 못 읽으면(SDK 미지원) 임시 크레덴셜을 env 로 직접 넘긴다.
# eval "$(aws configure export-credentials --format env)"

# 배포파일을 이 과제의 app/ 로 복사 — s3.tf 와 이미지 빌드가 app/ 를 직접 읽는다 (원본은 shared, 수정 금지)
cp ../../shared/provided/task-1/* app/

# 대회 당일 바뀌는 값은 tfvars 로 — 1·2차 apply 가 같은 값을 쓴다
cat > terraform/terraform.tfvars <<'EOF'
player_number = "00"
bucket_suffix = "abcd"
EOF
```

### 1) [본 PC] Terraform 1차

```bash
cd terraform
terraform init
terraform apply
terraform output -json > ../outputs.json

# S3 릴레이 (VPC CloudShell 은 업로드 UI 없음. _transfer/ 는 채점 전 삭제 — README step 9)
BUCKET=$(jq -r '.s3_bucket_name.value' ../outputs.json)
aws s3 cp ../outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf ../task.tgz -C .. k8s
aws s3 cp ../task.tgz "s3://$BUCKET/_transfer/task.tgz"
```

### 2) → README.md step 2 (일반 CloudShell — 이미지 빌드/푸시)

### 3) [본 PC] EKS 클러스터 (eksctl)

```bash
cd ../eksctl
export VPC_ID=$(jq -r '.vpc_id.value' ../outputs.json)
export CP_EXTRA_SG_ID=$(jq -r '.eks_cp_extra_sg_id.value' ../outputs.json)
export NODE_SHARED_SG_ID=$(jq -r '.eks_shared_node_sg_id.value' ../outputs.json)
export PRIV_SUBNET_A=$(jq -r '.private_subnet_ids.value["wsc2026-skills-app-sub-a"]' ../outputs.json)
export PRIV_SUBNET_B=$(jq -r '.private_subnet_ids.value["wsc2026-skills-app-sub-b"]' ../outputs.json)
export EKS_KMS_ARN=$(jq -r '.eks_kms_arn.value' ../outputs.json)
export BOOK_POD_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.book_pod' ../outputs.json)
export LBC_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.lbc' ../outputs.json)
export FLUENTBIT_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.fluentbit' ../outputs.json)
export GRAFANA_ROLE_ARN=$(jq -r '.pod_identity_role_arns.value.grafana' ../outputs.json)

# 치환 전: cluster.yaml 이 요구하는 env 가 전부 등록됐는지 검사.
# envsubst 는 누락된 env 를 빈 문자열로 조용히 치환하므로 이 검사가 없으면 20분 뒤 create 가 깨진다.
missing=$(for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' cluster.yaml | tr -d '${}' | sort -u); do
  [ -z "${!v}" ] && echo "$v"; done)
[ -z "$missing" ] && envsubst < cluster.yaml > cluster.rendered.yaml \
  || echo "env 누락: $missing — .env 를 다시 source"

# 치환 후: 잔여 ${} 가 없어야 함
grep -n '\${' cluster.rendered.yaml && echo '치환 누락!' || echo OK

# 셸 재시작 대비 — .env 통째로 재작성 (작업 규칙 6)
for v in AWS_DEFAULT_REGION VPC_ID CP_EXTRA_SG_ID NODE_SHARED_SG_ID \
  PRIV_SUBNET_A PRIV_SUBNET_B EKS_KMS_ARN BOOK_POD_ROLE_ARN LBC_ROLE_ARN \
  FLUENTBIT_ROLE_ARN GRAFANA_ROLE_ARN; do echo "export $v=\"${!v}\""; done > ../.env

eksctl create cluster -f cluster.rendered.yaml   # 약 20분, 완료 시 자동 private 전환
aws eks describe-cluster --name wsc2026-eks-cluster \
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true
# 생성이 끊겨 true 로 남았으면:
# aws eks update-cluster-config --name wsc2026-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

### 4~6) → README.md step 4·5·6 (bastion)

bastion 접속만 bash 로:

```bash
cd ../terraform   # step 3 이 eksctl 에서 끝남
aws ssm start-session --target "$(terraform output -raw bastion_instance_id)"
```

### 7) [본 PC] Terraform 2차

```bash
cd ../terraform
terraform apply -var="enable_cdn=true"
terraform output -raw cloudfront_domain
```

### 8) → README.md step 8 (bastion — E2E 검증)

### 9) [bastion → 본 PC] 작업물 백업

bastion 쪽 명령은 README.md step 9 와 동일. 본 PC 명령만 bash 로:

```bash
# cwd = terraform
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 cp "s3://$BUCKET/_transfer/_backup.tgz" ../_backup.tgz
mkdir -p ../_backup && tar xzf ../_backup.tgz -C ../_backup
# ../_backup/k8s 를 저장소 k8s/ 와 대조해 bastion 에서 고친 내용을 반영한다
```

### 9-2) → README.md step 9-2 (VPC CloudShell — mark.sh 로 채점 경로 확인)

### 9-3) [본 PC] 채점 전 정리

```bash
aws s3 rm "s3://$BUCKET/_transfer/" --recursive   # static/ 만 남긴다 (mark 6-1)
terraform apply -var="enable_cdn=true" -var="enable_bastion=false"   # bastion 제거
```

### 10) 전체 destroy (채점 종료 후)

10-1(퍼블릭 전환)은 aws CLI 라 bash 에서도 README.md step 10 과 명령이 동일하다.
그 뒤는 bash 로 옮긴다.

```bash
cd ../eksctl                                     # step 7 이후 cwd = terraform
eksctl delete cluster -f cluster.rendered.yaml

# dynamodb.tf 는 고치지 않는다 (mark 2-1 검사 대상)
aws dynamodb update-table --table-name wsc2026-book-table --no-deletion-protection-enabled

# force_destroy 미설정 — 객체가 남으면 destroy 가 실패한다
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws s3 rm "s3://$BUCKET" --recursive

cd ../terraform && terraform destroy   # enable_cdn 기본값(false) → data.aws_lb 조회 생략
```
