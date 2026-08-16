# 본 PC 가 Linux 일 때의 런북 (module-4-container-logging)

[README.md](README.md) 의 본 PC 단계(terraform·eksctl)를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계(0·3~8)도 자리에 stub 으로 표시했다.
스니펫은 zsh/bash 겸용이다(붙여넣기 실행 대비: `exit` 금지, if 게이트로만 차단).

### 0) [CloudShell] IAM 권한 조기 검증

[README.md](README.md) 0단계 수행.

### 1) [본 PC] 준비 + Terraform

```bash
cd module-4-container-logging
export KUBECONFIG="$PWD/kubeconfig"   # eksctl 전용 (kubectl 은 CloudShell 에서 쓴다)
zip -r /tmp/m4.zip k8s helm cs-deploy.sh
zip -j /tmp/m4.zip app/Dockerfile ../provided/module-4/app.py ../mark/mark4-2026-08-04.sh   # -j: 경로 없이 루트에
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC] EKS 클러스터 생성 (~15분)

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```bash
cd ../eksctl
export ACCOUNT_ID=$(terraform -chdir=../terraform output -raw account_id)
export VPC_ID=$(terraform -chdir=../terraform output -raw vpc_id)
export PRIV_SUBNET_A=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '.["o11y-sn-priv-a"]')
export PRIV_SUBNET_C=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '.["o11y-sn-priv-c"]')
# envsubst 는 unset 변수도 빈 문자열로 치환하므로 치환 전 비어있음 검사 필수
if [ -n "$ACCOUNT_ID" ] && [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_C" ]; then
  echo "$ACCOUNT_ID $VPC_ID $PRIV_SUBNET_A $PRIV_SUBNET_C"
else echo "STOP: terraform output 값 누락"; fi
```

**② 치환**

```bash
envsubst '${ACCOUNT_ID} ${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_C}' < cluster.yaml > cluster.rendered.yaml
```

**③ 치환 확인**

```bash
if grep -q '\${' cluster.rendered.yaml; then echo "STOP: 미치환 값 존재"; else grep -nE 'id:|arn:aws' cluster.rendered.yaml; fi
```

**④ 적용**

```bash
eksctl create cluster -f cluster.rendered.yaml
```

### 3) [CloudShell — 2단계 대기 중 병렬] 전송 + 이미지 빌드 & ECR push

[README.md](README.md) 3단계 수행 (업로드할 zip 은 `/tmp/m4.zip`).

### 4) [CloudShell] 클러스터 접속 확인 + 노드 검증

[README.md](README.md) 4단계 수행. `Unauthorized` 시에만 아래를 본 PC 에서 실행:

```bash
aws eks create-access-entry --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-1
aws eks associate-access-policy --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> \
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region ap-northeast-1
```

### 5) [CloudShell] LBC·Loki·Grafana·k8s 배포

[README.md](README.md) 5단계 수행.

### 6) [CloudShell] pod·TG healthy 확인

[README.md](README.md) 6단계 수행.

### 7) [CloudShell] 종단 스모크

[README.md](README.md) 7단계 수행 (Grafana UI 는 본 PC 브라우저).

### 8) [CloudShell] 셀프 채점

[README.md](README.md) 8단계 수행.

## Teardown

CloudShell 단계는 [README.md](README.md) Teardown 을 먼저 수행한 뒤:

```bash
cd eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
