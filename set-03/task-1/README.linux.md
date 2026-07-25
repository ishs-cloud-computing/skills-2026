# 본 PC 가 Linux 일 때의 런북 (set-03 / task-1)

[README.md](README.md) 의 본 PC 단계(0·1·3·7·10)를 bash 로 옮긴 것. CloudShell 단계(2·4·5·6·8·9)는
README.md 와 동일. 설계 근거는 [deployment.md](../../docs/src/content/docs/setlist/set-03/task-1/deployment.md),
주의/함정·설계 이력은 [NOTES.md](NOTES.md).

### 0) [본 PC] 도구 준비 + 작업용 IAM 사용자 + 사전 변수

필요 도구: AWS CLI v2 · Terraform · eksctl · jq · gettext(envsubst) (Docker 불필요).

```bash
# root 자격증명으로 1회만 실행
aws iam create-user --user-name wsc2026-admin
aws iam attach-user-policy --user-name wsc2026-admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-access-key --user-name wsc2026-admin \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text

# 출력된 키로 프로파일 등록 — CloudShell 단계(2·4)에서도 같은 키를 입력하므로 잘 보관
aws configure --profile wsc2026        # region = ap-northeast-2

# local .env (작업 규칙 6, .gitignore 등록됨)
cat > .env <<'EOF'
export AWS_PROFILE=wsc2026
export AWS_DEFAULT_REGION=ap-northeast-2
EOF
source .env
aws sts get-caller-identity            # arn:...:user/wsc2026-admin 확인

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
tar czf /tmp/wsc2026-cs.tgz -C .. k8s
aws s3 cp /tmp/wsc2026-cs.tgz "s3://$BUCKET/_transfer/wsc2026-cs.tgz"
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

envsubst < cluster.yaml > cluster.rendered.yaml
grep '\${[A-Z]' cluster.rendered.yaml && echo '치환 누락'   # 출력 없어야 함 (주석의 ${...} 는 제외)

eksctl create cluster -f cluster.rendered.yaml   # 약 20분, 완료 시 자동 private 전환
aws eks describe-cluster --name wsc2026-eks-cluster \
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,endpointPrivateAccess]'   # false, true
# 생성이 끊겨 true 로 남았으면:
# aws eks update-cluster-config --name wsc2026-eks-cluster --resources-vpc-config endpointPublicAccess=false
```

### 4~6) → README.md step 4·5·6 (VPC CloudShell)

### 7) [본 PC] Terraform 2차

```bash
cd ../terraform
terraform apply -var="enable_cdn=true"
terraform output -raw cloudfront_domain
```

### 8~9) → README.md step 8·9 (VPC CloudShell — E2E 검증, 정리)

### 10) 전체 destroy (채점 종료 후)

10-1(ingress 삭제)은 README.md step 10 과 같다. 본 PC 명령만 bash 로 옮긴다.

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
