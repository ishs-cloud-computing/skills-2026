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

## 0. 시작 전 확인 (대회 시작 직후 1회)

**CloudShell 접속을 확인**한다. 이 모듈은 로컬에 Docker가 없어 이미지 build/push(3단계)가 CloudShell 필수 경로이므로, 접속이 안 되면 모듈 전체가 막힌다. 활성 탭이 이전 세션의 VPC 환경이면 기본 리전 탭으로 전환한다(그 상태에선 파일 업로드가 비활성이다).

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
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -json > outputs.json   # 커밋 금지 (.gitignore)
```

주요 output을 세션 변수로 로드하고 `.env.ps1`(본 PC 재접속용)·`.env`(CloudShell 업로드용)로 저장한다:

```powershell
$env:ACCOUNT_ID           = terraform -chdir=terraform output -raw account_id
$env:REGION               = "us-west-2"
$env:VPC_ID               = terraform -chdir=terraform output -raw vpc_id
$SN                       = terraform -chdir=terraform output -json private_subnet_ids | ConvertFrom-Json
$env:PRIV_SUBNET_A        = $SN.'skills-sqs-sn-priv-a'
$env:PRIV_SUBNET_B        = $SN.'skills-sqs-sn-priv-b'
$env:QUEUE_URL            = terraform -chdir=terraform output -raw queue_url
$env:ECR_IMAGE            = "$(terraform -chdir=terraform output -raw ecr_repo_url):latest"
$env:KEDA_POLICY_ARN      = terraform -chdir=terraform output -raw keda_policy_arn
$env:KARPENTER_POLICY_ARN = terraform -chdir=terraform output -raw karpenter_policy_arn
$env:WORKER_POLICY_ARN    = terraform -chdir=terraform output -raw worker_policy_arn
$env:NODE_ROLE_ARN        = terraform -chdir=terraform output -raw karpenter_node_role_arn
$env:NODE_ROLE_NAME       = terraform -chdir=terraform output -raw karpenter_node_role_name

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

# .env 는 CloudShell(bash)이 source 하므로 반드시 LF 로 쓴다.
# Set-Content 는 파일 끝 개행을 CRLF 로 써서 마지막 줄(ECR_IMAGE)에 \r 이 붙고,
# docker build/push 가 잘못된 태그로 실패한다 — WriteAllText + LF 치환으로 회피.
$envBody = @"
export ACCOUNT_ID=$env:ACCOUNT_ID
export REGION=$env:REGION
export VPC_ID=$env:VPC_ID
export PRIV_SUBNET_A=$env:PRIV_SUBNET_A
export PRIV_SUBNET_B=$env:PRIV_SUBNET_B
export QUEUE_URL=$env:QUEUE_URL
export ECR_IMAGE=$env:ECR_IMAGE
"@
[IO.File]::WriteAllText("$PWD\.env", ($envBody.Replace("`r`n", "`n") + "`n"))

. .\.env.ps1   # 재접속 시: module-4-sqs-scaling 디렉터리에서 `. .\.env.ps1` 만 다시 실행
```

`.env`(CloudShell 업로드용)는 docker build/push에만 필요한 값만 담는다 — ARN·role 계열은 본 PC의 `.env.ps1`에만 있으면 된다(CloudShell은 eksctl/k8s 렌더링을 하지 않는다).

## 2. cluster.yaml 렌더링 + eksctl create (~20분)

렌더와 실행을 붙이지 않는다. 2-1 환경 변수 검토 → 2-2 렌더 → 2-3 렌더 결과 값 검토 → 2-4 실행 순으로 끊어서, 잘못된 값이 20분짜리 `eksctl create` 에 들어가기 전에 눈으로 잡는다.

### 2-1. 환경 변수 검토

```powershell
'VPC_ID','PRIV_SUBNET_A','PRIV_SUBNET_B','KEDA_POLICY_ARN','KARPENTER_POLICY_ARN','WORKER_POLICY_ARN','NODE_ROLE_ARN' |
  ForEach-Object { "{0,-22} = {1}" -f $_, [Environment]::GetEnvironmentVariable($_) }
```

- 빈 값이 하나라도 있으면 여기서 멈추고 1단계의 `. .\.env.ps1` 부터 다시 한다.
- `VPC_ID` 는 `vpc-`, 서브넷 2개는 `subnet-` 으로 시작하고 서로 달라야 한다.
- ARN 4개는 `arn:aws:iam::<ACCOUNT_ID>:` 로 시작하고 계정번호가 `$env:ACCOUNT_ID` 와 같아야 한다. `NODE_ROLE_ARN` 만 `:role/`, 나머지 3개는 `:policy/` 다.

### 2-2. 렌더

```powershell
New-Item -ItemType Directory -Force eksctl/rendered | Out-Null
$Y = Get-Content eksctl/cluster.yaml -Raw
$Y = $Y.Replace('${VPC_ID}', $env:VPC_ID).Replace('${PRIV_SUBNET_A}', $env:PRIV_SUBNET_A).Replace('${PRIV_SUBNET_B}', $env:PRIV_SUBNET_B)
$Y = $Y.Replace('${KEDA_POLICY_ARN}', $env:KEDA_POLICY_ARN).Replace('${KARPENTER_POLICY_ARN}', $env:KARPENTER_POLICY_ARN)
$Y = $Y.Replace('${WORKER_POLICY_ARN}', $env:WORKER_POLICY_ARN).Replace('${NODE_ROLE_ARN}', $env:NODE_ROLE_ARN)
$Y | Set-Content eksctl/rendered/cluster.yaml
```

### 2-3. 렌더 결과 값 검토

```powershell
Select-String -Path eksctl/rendered/cluster.yaml -Pattern '\$\{'          # 출력 없어야 정상 (미치환 잔여)
Select-String -Path eksctl/rendered/cluster.yaml -Pattern 'vpc-|subnet-|arn:aws:'
```

치환된 줄만 뽑힌다. `id:` 2줄(서브넷 a/b)이 서로 다른지, `principalARN` 이 role ARN 인지, `attachPolicyARNs` 3개가 keda/karpenter/worker 순서에 맞게 들어갔는지 확인한다. 첫 명령에 한 줄이라도 잡히면 실행하지 않는다.

### 2-4. eksctl create

```powershell
eksctl create cluster -f eksctl/rendered/cluster.yaml   # kubeconfig 는 $env:KUBECONFIG(모듈 경로)에 기록됨
```

### 2-5. 완료 확인

`eksctl create`가 `$env:KUBECONFIG`(모듈 경로)에 컨텍스트를 자동 기록하므로 별도 `aws eks update-kubeconfig`는 불필요하다 — 아래로 클러스터 생성과 컨텍스트 연결을 함께 확인한다:

```powershell
kubectl config current-context   # 모듈 kubeconfig 파일 경로가 그대로 나오면 연결 확인
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate
```

Fargate Node 2개(keda/karpenter용)가 나오면 4단계로 진행한다.

## 3. [CloudShell — 2단계 eksctl 생성 대기 중 병렬] worker 이미지 build/push

빌드에 필요한 3개 파일(`app/Dockerfile`, `provided/module-4/worker.py`, `.env`)을 module 홈폴더(`module-4-sqs-scaling/`)에 zip으로 묶은 뒤 그 zip 하나만 업로드한다 — 파일 3개를 개별 업로드하는 것보다 실수(빠뜨림·다른 리전 탭 재업로드)가 적다.

```powershell
Compress-Archive -Path app\Dockerfile,..\provided\module-4\worker.py,.env -DestinationPath m4.zip -Force
```

**us-west-2 CloudShell**에서 작업 → 파일 업로드로 `m4.zip`을 올린다. 업로드 파일은 항상 홈(`/home/cloudshell-user`)에 평평하게 저장되고, CloudShell 홈은 리전별로 분리되므로 반드시 us-west-2 탭에서 올려야 한다.
```bash
mkdir -p ~/module4-build && cd ~/module4-build
unzip -oj ~/m4.zip
sed -i 's/\r$//' .env   # CRLF 가드 (멱등) — \r 이 섞이면 ECR_IMAGE 태그가 깨진다
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

2단계와 같이 4단계로 끊는다.

### 5-1. 환경 변수 검토

```powershell
'ECR_IMAGE','QUEUE_URL','REGION','NODE_ROLE_NAME' |
  ForEach-Object { "{0,-16} = {1}" -f $_, [Environment]::GetEnvironmentVariable($_) }
```

- 빈 값이 있으면 1단계의 `. .\.env.ps1` 부터 다시 한다.
- `ECR_IMAGE` 는 `<ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-worker:latest` 형태이고 끝에 `\r` 같은 군더더기가 없어야 한다(3단계에서 push 한 태그와 정확히 같아야 pull 된다).
- `QUEUE_URL` 은 `https://sqs.us-west-2.amazonaws.com/<ACCOUNT_ID>/skills-sqs-queue`, `NODE_ROLE_NAME` 은 ARN 이 아니라 **역할 이름만** 이다.

### 5-2. 렌더

```powershell
New-Item -ItemType Directory -Force k8s/rendered | Out-Null
Get-ChildItem k8s/*.yaml | ForEach-Object {
  (Get-Content $_ -Raw).Replace('${ECR_IMAGE}', $env:ECR_IMAGE).Replace('${QUEUE_URL}', $env:QUEUE_URL).Replace('${REGION}', $env:REGION).Replace('${NODE_ROLE_NAME}', $env:NODE_ROLE_NAME) | Set-Content "k8s/rendered/$($_.Name)"
}
```

### 5-3. 렌더 결과 값 검토

```powershell
Select-String -Pattern '\$\{' k8s/rendered/*.yaml                          # 출력 없어야 정상 (미치환 잔여)
Select-String -Pattern 'image:|queueURL|awsRegion|role:|value:' k8s/rendered/*.yaml
kubectl apply --dry-run=server -f k8s/rendered/                            # 클러스터 스키마 검증 (실제 적용 없음)
```

`image:` 가 3단계에서 push 한 태그와 같은지, ScaledObject 의 `queueURL`·Deployment 의 `value:` 2줄(SQS_QUEUE_URL·AWS_REGION)이 6단계 검증에 쓸 큐·리전과 같은지, `role:` 이 Karpenter 노드 역할 **이름**인지 확인한다. 미치환이 잡히거나 dry-run 이 실패하면 실행하지 않는다.

### 5-4. apply

```powershell
kubectl apply -f k8s/rendered/   # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
```

`namespace/skills-sqs`에 `missing the kubectl.kubernetes.io/last-applied-configuration annotation` 경고가 뜨는 건 정상이다 — eksctl Fargate profile이 네임스페이스를 먼저 만들어서 나며, 자동 패치된다.

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
  aws sqs get-queue-attributes --region us-west-2 --queue-url $env:QUEUE_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
  kubectl get deployment sqs-worker -n skills-sqs
  kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
  kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
  kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
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
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster --region us-west-2
```

## 8. 채점 직전 경량 상태 확인

4-5 감점 우려는 공식 예상 출력(`provided/008_chall_2nd_patched_0801.md` 4-5 판정 기준)이 "min 0으로 채점 직후 Worker Pod가 없을 수 있으므로 Worker Pod의 EC2 배치는 4-6 Scale Out 출력 결과를 포함해 판정할 수 있다"고 명시해 해소됐다. 스케일아웃 파이프라인 실동작 검증은 6단계에서 이미 마쳤으므로(12건 발송, 소진·복귀까지 확인) 채점 직전에 SQS 메시지를 다시 보낼 필요는 없다 — 6단계 이후 상태 변경 없이 그대로인지만 가볍게 확인한다:

```powershell
kubectl get pods -n keda
kubectl get pods -n karpenter
kubectl get scaledobject,triggerauthentication -n skills-sqs
kubectl get nodepool,ec2nodeclass
# 컨트롤러 pod Running, ScaledObject/TriggerAuthentication/NodePool/EC2NodeClass 존재 확인되면 채점 시작
```

[CloudShell] 셀프 채점:

```bash
# mark/mark2-4.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark2-4.sh
bash mark2-4.sh
```

`mark2-4.sh`는 CloudShell에 kubectl이 없어 설치부터 하고 4-6에서 `sleep 60`을 3회 돈다 — 실측 **약 11분**. 다른 모듈 채점(각 1~3분)과 달리 시간을 따로 잡는다.

## 9. Teardown

```powershell
kubectl delete -f k8s/rendered/ --wait=false
helm uninstall keda -n keda
helm uninstall karpenter -n karpenter
eksctl delete cluster -f eksctl/rendered/cluster.yaml
terraform -chdir=terraform destroy -auto-approve
```

- `--wait=false`를 쓰는 이유: 기본 동작으로 돌리면 삭제 메시지를 다 출력한 뒤에도 kubectl이 종료되지 않고 매달려(실측 15분+) 뒤의 `helm uninstall`이 아예 실행되지 않는다.
- 그래도 매달리면 kubectl을 끊고 다음 단계로 진행해도 된다. 이때 `helm uninstall`이 `Failed to purge the release: secrets "sh.helm.release.v1.keda.v1" not found` 경고를 내도 리소스는 제거된 상태라 무시한다.
- `eksctl delete cluster`는 실측 약 8분(Fargate profile 3개를 프로필당 ~2분씩 순차 삭제).
