# 본 PC 가 Linux 일 때의 런북 (module-3-eks-scaling)

[README.md](README.md) 의 본 PC 단계(terraform·eksctl)를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계(3~6)도 자리에 stub 으로 표시했다.
스니펫은 zsh/bash 겸용이다(붙여넣기 실행 대비: `exit` 금지, if 게이트로만 차단).

### 0) [본 PC] 준비 — 터미널 고정 + CloudShell 전송 zip

```bash
cd module-3-eks-scaling
export KUBECONFIG="$PWD/kubeconfig"   # eksctl 전용 (kubectl 은 CloudShell 에서 쓴다)
rm -f m3.zip
zip -r m3.zip k8s cs-deploy.sh
zip -j m3.zip ../provided/module-3/* ../mark/mark3-2026-08-01.sh   # -j: 경로 없이 루트에 담는다
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
if [ -n "$ACCOUNT_ID" ] && [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_C" ]; then
  envsubst '${ACCOUNT_ID} ${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_C}' < cluster.yaml > cluster.rendered.yaml
  if grep -n '\${' cluster.rendered.yaml; then echo "STOP: 미치환 값 존재"
  else eksctl create cluster -f cluster.rendered.yaml; fi
else echo "STOP: terraform output 값 누락"; fi
```

### 3) [CloudShell — 2단계 대기 중 병렬] 전송 + 이미지 빌드 & ECR push

[README.md](README.md) 3단계 수행 (업로드할 zip 은 `m3.zip`).

### 4) [CloudShell] 클러스터 접속 확인

[README.md](README.md) 4단계 수행. `Unauthorized` 시에만 아래를 본 PC 에서 실행:

```bash
aws eks create-access-entry --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-2
aws eks associate-access-policy --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region ap-northeast-2
```

### 5) [CloudShell] KEDA·Karpenter·k8s 배포

[README.md](README.md) 5단계 수행.

### 6) [CloudShell] 검증 + 셀프 채점

[README.md](README.md) 6단계 수행.

## Teardown

CloudShell 단계는 [README.md](README.md) Teardown 을 먼저 수행한 뒤:

```bash
cd eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
