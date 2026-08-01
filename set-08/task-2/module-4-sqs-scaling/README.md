# Module 4 — SQS Scaling (us-west-2)

SQS 큐 길이에 따라 KEDA가 Worker Pod를, Karpenter가 EC2 Worker Node를 스케일링하는 구조. 채점은 CloudShell에서 `mark/mark2-4.sh` 실행.
본 PC가 Linux면 [README.linux.md](README.linux.md)를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-4-sqs-scaling/
├── terraform/
│   ├── vpc.tf                 # VPC + private 서브넷(karpenter.sh/discovery 태그)
│   ├── sqs.tf                 # skills-sqs-queue
│   ├── ecr.tf                 # skills-sqs-worker 저장소
│   ├── iam.tf                 # KEDA·worker·Karpenter 정책 + KarpenterNodeRole
│   └── {versions,variables,data,outputs}.tf
├── eksctl/
│   └── cluster.yaml           # skills-sqs-cluster + Fargate profile 3개 + IRSA SA 3개
├── k8s/                       # 번호 순 apply
│   ├── 00-namespace.yaml
│   ├── 10-karpenter-nodepool.yaml
│   ├── 20-deployment.yaml
│   └── 30-keda-scaledobject.yaml
├── app/
│   └── Dockerfile              # 빌드 컨텍스트에 provided/module-4/worker.py 복사 필요 (3단계)
├── README.md
└── README.linux.md

# 앱 소스: task-2/provided/module-4/worker.py (제공 원본, 수정 금지)
# 채점: task-2/mark/mark2-4.sh (CloudShell, us-west-2)
```

## 0. IAM 권한 프로브 (대회 시작 직후 1회)

```powershell
'{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' | Set-Content -Path iam-probe-trust.json
aws iam create-role --role-name skills-iam-probe --assume-role-policy-document file://iam-probe-trust.json
if ($LASTEXITCODE -eq 0) {
  aws iam delete-role --role-name skills-iam-probe
  if ($LASTEXITCODE -ne 0) { Write-Host "삭제 거부 — skills-iam-probe role 잔존 상태를 감독관에게 확인" }
} else {
  Write-Host "STOP: AccessDenied — IAM 미지급. 감독관 문의 (module-1·3·4 진행 불가)"
}
Remove-Item -Force iam-probe-trust.json
```

이 모듈에서 만드는 클러스터 전용 kubeconfig를 지금부터 사용한다 (터미널 1개 = 클러스터 1개):

```powershell
cd module-4-sqs-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```powershell
$env:KUBECONFIG = "$PWD\kubeconfig"
aws eks update-kubeconfig --name skills-sqs-cluster --region us-west-2 --kubeconfig $env:KUBECONFIG
. .\.env.ps1
```

## 1. terraform apply

```powershell
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json   # 커밋 금지 (.gitignore)
```

주요 output을 세션 변수로 로드하고 `.env.ps1`(본 PC 재접속용)·`.env`(CloudShell 업로드용)로 저장한다:

```powershell
$env:ACCOUNT_ID           = terraform output -raw account_id
$env:REGION               = "us-west-2"
$env:VPC_ID               = terraform output -raw vpc_id
$SN                       = terraform output -json private_subnet_ids | ConvertFrom-Json
$env:PRIV_SUBNET_A        = $SN.'skills-sqs-sn-priv-a'
$env:PRIV_SUBNET_B        = $SN.'skills-sqs-sn-priv-b'
$env:QUEUE_URL            = terraform output -raw queue_url
$env:ECR_IMAGE            = "$(terraform output -raw ecr_repo_url):latest"
$env:KEDA_POLICY_ARN      = terraform output -raw keda_policy_arn
$env:KARPENTER_POLICY_ARN = terraform output -raw karpenter_policy_arn
$env:WORKER_POLICY_ARN    = terraform output -raw worker_policy_arn
$env:NODE_ROLE_ARN        = terraform output -raw karpenter_node_role_arn
$env:NODE_ROLE_NAME       = terraform output -raw karpenter_node_role_name
cd ..

@"
`$env:ACCOUNT_ID           = "$env:ACCOUNT_ID"
`$env:REGION               = "$env:REGION"
`$env:VPC_ID               = "$env:VPC_ID"
`$env:PRIV_SUBNET_A        = "$env:PRIV_SUBNET_A"
`$env:PRIV_SUBNET_B        = "$env:PRIV_SUBNET_B"
`$env:QUEUE_URL            = "$env:QUEUE_URL"
`$env:ECR_IMAGE            = "$env:ECR_IMAGE"
`$env:KEDA_POLICY_ARN      = "$env:KEDA_POLICY_ARN"
`$env:KARPENTER_POLICY_ARN = "$env:KARPENTER_POLICY_ARN"
`$env:WORKER_POLICY_ARN    = "$env:WORKER_POLICY_ARN"
`$env:NODE_ROLE_ARN        = "$env:NODE_ROLE_ARN"
`$env:NODE_ROLE_NAME       = "$env:NODE_ROLE_NAME"
"@ | Set-Content .env.ps1

@"
export ACCOUNT_ID=$env:ACCOUNT_ID
export REGION=$env:REGION
export VPC_ID=$env:VPC_ID
export PRIV_SUBNET_A=$env:PRIV_SUBNET_A
export PRIV_SUBNET_B=$env:PRIV_SUBNET_B
export QUEUE_URL=$env:QUEUE_URL
export ECR_IMAGE=$env:ECR_IMAGE
"@ | Set-Content .env

. .\.env.ps1   # 재접속 시: module-4-sqs-scaling 디렉터리에서 `. .\.env.ps1` 만 다시 실행
```

`.env`(CloudShell 업로드용)는 docker build/push에만 필요한 값만 담는다 — ARN·role 계열은 본 PC의 `.env.ps1`에만 있으면 된다(CloudShell은 eksctl/k8s 렌더링을 하지 않는다).

## 2. cluster.yaml 렌더링 + eksctl create (~20분)

```powershell
cd eksctl
if (!$env:VPC_ID -or !$env:PRIV_SUBNET_A -or !$env:PRIV_SUBNET_B -or !$env:KEDA_POLICY_ARN -or !$env:KARPENTER_POLICY_ARN -or !$env:WORKER_POLICY_ARN -or !$env:NODE_ROLE_ARN) { throw "STOP: terraform output 값 누락" }
New-Item -ItemType Directory -Force rendered | Out-Null
$Y = Get-Content cluster.yaml -Raw
$Y = $Y.Replace('${VPC_ID}', $env:VPC_ID).Replace('${PRIV_SUBNET_A}', $env:PRIV_SUBNET_A).Replace('${PRIV_SUBNET_B}', $env:PRIV_SUBNET_B)
$Y = $Y.Replace('${KEDA_POLICY_ARN}', $env:KEDA_POLICY_ARN).Replace('${KARPENTER_POLICY_ARN}', $env:KARPENTER_POLICY_ARN)
$Y = $Y.Replace('${WORKER_POLICY_ARN}', $env:WORKER_POLICY_ARN).Replace('${NODE_ROLE_ARN}', $env:NODE_ROLE_ARN)
$Y | Set-Content rendered/cluster.yaml
if (Select-String -Path rendered/cluster.yaml -Pattern '\$\{') { throw "STOP: 미치환 값 존재" }
eksctl create cluster -f rendered/cluster.yaml   # kubeconfig 는 $env:KUBECONFIG(모듈 경로)에 기록됨
cd ..
```

## 3. [CloudShell — 2단계 eksctl 생성 대기 중 병렬] worker 이미지 build/push

CloudShell Actions → Upload file로 `app/Dockerfile`, `provided/module-4/worker.py`, `.env`를 업로드한다 (CloudShell 홈 디렉터리에 저장됨).

```bash
mkdir -p ~/module4-build && cd ~/module4-build
cp ~/Dockerfile ~/worker.py ~/.env .
source .env
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t "${ECR_IMAGE}" .
docker push "${ECR_IMAGE}"
```

## 4. helm — Karpenter·KEDA (버전 미핀: 최신 안정)

```powershell
helm install karpenter oci://public.ecr.aws/karpenter/karpenter -n karpenter `
  --set settings.clusterName=skills-sqs-cluster `
  --set serviceAccount.create=false --set serviceAccount.name=karpenter `
  --set replicas=1 --set dnsPolicy=Default --wait
  # dnsPolicy=Default: Fargate 기동 시 CoreDNS 의존 제거 (VPC 리졸버 직행)

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda -n keda `
  --set serviceAccount.operator.create=false `
  --set serviceAccount.operator.name=keda-operator --wait
```

확인:

```powershell
kubectl get pods -n karpenter
kubectl get pods -n keda
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate
```

## 5. k8s manifest 렌더링 + apply

```powershell
cd k8s
if (!$env:ECR_IMAGE -or !$env:QUEUE_URL -or !$env:REGION -or !$env:NODE_ROLE_NAME) { throw "STOP: terraform output 값 누락" }
New-Item -ItemType Directory -Force rendered | Out-Null
Get-ChildItem *.yaml | ForEach-Object {
  (Get-Content $_ -Raw).Replace('${ECR_IMAGE}', $env:ECR_IMAGE).Replace('${QUEUE_URL}', $env:QUEUE_URL).Replace('${REGION}', $env:REGION).Replace('${NODE_ROLE_NAME}', $env:NODE_ROLE_NAME) | Set-Content "rendered/$($_.Name)"
}
if (Select-String -Pattern '\$\{' rendered\*.yaml) { throw "STOP: 미치환 값 존재" }
kubectl apply -f rendered/   # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
cd ..
```

큐가 비어 있으면 minReplicaCount 0이라 pod 0개가 정상이다 — scale-out 확인은 6단계에서 한다. apply 결과는 리소스 존재로만 확인:

```powershell
kubectl get scaledobject,triggerauthentication -n skills-sqs
kubectl get nodepool,ec2nodeclass
```

## 6. 스케일 검증 (mark2-4.sh 4-6 시나리오 수동 재현)

```powershell
1..12 | ForEach-Object {
  aws sqs send-message --region us-west-2 --queue-url $env:QUEUE_URL --message-body "verify-$_" | Out-Null
}
foreach ($t in 60, 120, 180) {
  Start-Sleep -Seconds 60
  Write-Host "=== after ${t}s ==="
  aws sqs get-queue-attributes --region us-west-2 --queue-url $env:QUEUE_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table
  kubectl get deployment sqs-worker -n skills-sqs
  kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
  kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
}
```

`ApproximateNumberOfMessages=0` 확인 후 cooldownPeriod(30s)·consolidateAfter(30s) 경과 대기, pod 0·노드 0 복귀 확인:

```powershell
Start-Sleep -Seconds 90
kubectl get pods -n skills-sqs -l app=sqs-worker
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool
```

## 7. [CloudShell] kubectl 확인 (협의회 필수 요구)

```bash
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes
```

`Unauthorized`가 나오면(채점 주체 ≠ 클러스터 생성자) CloudShell의 IAM ARN을 확인 후 본 PC에서 access entry를 추가한다:

```bash
aws sts get-caller-identity --query Arn --output text   # CloudShell 에서 ARN 확인
```

```powershell
aws eks create-access-entry --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region us-west-2
aws eks associate-access-policy --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> `
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster --region us-west-2
```

## 8. 채점 직전 사전 활성화

mark2-4.sh는 [4-5](Karpenter NodePool·EC2NodeClass·배치)를 [4-6](스케일아웃 검증, 12건 발송)보다 먼저 조회한다. minReplicaCount 0 설계상 큐가 비어 있으면 pod·노드가 0개인 상태가 정상이지만, 그 상태로 채점을 시작하면 4-5 시점에 아무 것도 조회되지 않는다. **purge는 하지 않는다** — 메시지는 5초/건으로 처리되고 cooldown 후 자연히 0으로 복귀하며, 채점 자체가 4-6에서 12건을 새로 발송한다. 대신 채점 시작 직전에 메시지를 미리 보내 pod·노드를 활성 상태로 만들어 둔다:

```powershell
1..6 | ForEach-Object {
  aws sqs send-message --region us-west-2 --queue-url $env:QUEUE_URL --message-body "pre-mark-$_" | Out-Null
}
# 노드 프로비저닝 포함 최대 3분 대기, Running pod 확인되면 즉시 진행
for ($i = 0; $i -lt 18; $i++) {
  Start-Sleep -Seconds 10
  $running = kubectl get pods -n skills-sqs -l app=sqs-worker --field-selector=status.phase=Running --no-headers 2>$null
  if ($running) { break }
}
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
# 위 두 명령에서 pod가 Running(≥1)이고 Karpenter 노드가 조회되면 채점 시작
```

[CloudShell] 셀프 채점:

```bash
# CloudShell 에서 mark/mark2-4.sh 를 git clone 또는 파일 업로드(Actions → Upload file)로 전송 후 실행.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark/mark2-4.sh
bash mark/mark2-4.sh
```

## 9. Teardown

```powershell
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
