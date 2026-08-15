# 본 PC 가 Linux 일 때의 런북 (set-07 / task-1)

[README.md](README.md) 의 **본 PC 단계(0·1·3·10)** 를 bash 로 옮긴 것.
step 2(일반 CloudShell)와 bastion/CloudShell 단계(4~9)는 리눅스라 README.md 와 동일하다.
리소스·순서·검증은 전부 같고 명령 문법만 다르다.

### 0) [본 PC] 사전 변수

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=<선수등번호>     # ExternalId / Grafana 계정에 사용
```

> 본 PC 는 terraform 전용이라 계정만 맞으면 신원은 무관하다. 채점 신원과의 일치는 클러스터를 만드는
> bastion 에서만 문제가 된다 (README.md step 4 의 인용문 참고).

### 1) [본 PC] Terraform (네트워크 + AWS 리소스)

```bash
cd terraform
terraform init
terraform apply -var="player_number=$NUM"
terraform output -json > ../outputs.json   # 작업 호스트로 넘길 값 (tfstate 는 넘기지 않는다)

export ACCOUNT_ID=$(jq -r '.account_id.value' ../outputs.json)
export BUCKET=$(jq -r '.s3_bucket_name.value' ../outputs.json)

# 재접속 대비 (작업 규칙 6, .gitignore 등록됨). 새 셸에선 task-1 에서 `source .env` 만 다시 실행
cat > ../.env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-2
export NUM=$NUM
export ACCOUNT_ID=$ACCOUNT_ID
export BUCKET=$BUCKET
EOF

# 작업 호스트는 파일 업로드 UI 가 없고 레포가 비공개라 git clone 도 불가 → S3 를 릴레이로 쓴다.
# _transfer/ 는 채점 전 step 10 에서 비운다 (web 버킷은 채점 대상 — mark.sh 3-1-A).
aws s3 cp ../outputs.json "s3://$BUCKET/_transfer/outputs.json"
tar czf /tmp/unicorn-cs.tgz -C .. eksctl k8s mark-2026-08-10.sh   # 2026-08-10 정정본. mark.sh 최초본은 대조용
aws s3 cp /tmp/unicorn-cs.tgz "s3://$BUCKET/_transfer/unicorn-cs.tgz"

# step 2(일반 CloudShell)의 이미지 빌드 재료
aws s3 cp ../app/Dockerfile "s3://$BUCKET/_transfer/Dockerfile"
aws s3 cp ../../../shared/provided/task-1/book "s3://$BUCKET/_transfer/book"
```

### 2) → README.md step 2 (일반 CloudShell — 이미지 빌드/푸시)

로컬에 Docker 가 있어도 CloudShell 에서 하는 편이 낫다 — ECR 로그인·푸시 경로가 채점 계정과 같고,
`--platform` 을 신경 쓸 필요가 없다.

### 3) [본 PC] 작업용 SSM bastion 생성 (수동 · 임시)

```bash
cd terraform   # outputs.json 은 ../outputs.json
source ../.env # 새 셸이면

SUBNET=$(jq -r '.private_subnet_ids.value["unicorn-subnet-priv-a"]' ../outputs.json)
MARK_SG=$(jq -r '.mark_sg_id.value' ../outputs.json)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)

# IAM: SSM 접속용만 (작업 권한은 4) 의 aws login --remote 로 주입)
aws iam create-role --role-name unicorn-bastion-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name unicorn-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name unicorn-bastion-profile
aws iam add-role-to-instance-profile --instance-profile-name unicorn-bastion-profile --role-name unicorn-bastion-role
sleep 10   # instance profile 전파 대기

# EC2 (인바운드 없음, IMDSv2 강제)
BID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.small \
  --iam-instance-profile Name=unicorn-bastion-profile \
  --subnet-id "$SUBNET" --security-group-ids "$MARK_SG" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=unicorn-bastion}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "bastion=$BID"   # step 10 삭제에 사용

aws ssm start-session --target "$BID"
```

### 4~9) → README.md step 4~9 (bastion / CloudShell)

step 9 의 **권한 게이트**(`kubectl auth can-i '*' '*'`)를 통과하기 전에는 step 10 으로 넘어가지 않는다.

### 10) [본 PC] 채점 전 정리 (배포 검증 후)

10-1(bastion 상태 백업)은 README.md 와 동일한 bash 다. 아래는 본 PC 쪽 10-2.
회수를 S3 정리보다 먼저 해야 복구 수단이 남는다.

```bash
source ../.env   # 새 셸이면 (task-1 에서 source .env)

# 백업 회수 — 레포 밖에 둔다
aws s3 cp "s3://$BUCKET/_transfer/unicorn-bastion-state.tgz" /tmp/

# bastion 삭제
BID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=unicorn-bastion Name=instance-state-name,Values=running \
  --query "Reservations[].Instances[].InstanceId" --output text)   # 3) 의 $BID 를 모를 때
aws ec2 terminate-instances --instance-ids "$BID"
aws ec2 wait instance-terminated --instance-ids "$BID"
aws iam remove-role-from-instance-profile --instance-profile-name unicorn-bastion-profile --role-name unicorn-bastion-role
aws iam delete-instance-profile --instance-profile-name unicorn-bastion-profile
aws iam detach-role-policy --role-name unicorn-bastion-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name unicorn-bastion-role

# S3 릴레이 제거 (web 버킷은 채점 대상 — mark.sh 3-1-A)
aws s3 rm "s3://$BUCKET/_transfer/" --recursive
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix _transfer/ --query 'Contents[].Key'  # null 확인
```

> **bastion 복구** — step 3 재실행 → README.md step 4 의 도구 설치 + `aws login --remote` 재실행 →
> `/tmp/unicorn-bastion-state.tgz` 를 `_transfer/` 로 재업로드 → bastion 에서 받아
> `tar xzf ~/unicorn-bastion-state.tgz -C ~` → `source ~/.env` + `aws eks update-kubeconfig`.
> 채점이 아직이면 복구 후 `_transfer/` 를 다시 비운다.
