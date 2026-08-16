# Module 3 — EKS Scaling (ap-northeast-2)

SQS 주문 큐 + EKS 1.35(tainted Addon NG) + ECR 이미지 앱 + KEDA(Pod 스케일링) + Karpenter(노드 스케일링). 채점은 CloudShell에서 `mark/mark3-2026-08-01.sh`(정정본) 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-3-eks-scaling/
├── terraform/
│   ├── vpc.tf               # 자체 VPC + pub/priv 서브넷 + NAT (priv 에 karpenter.sh/discovery 태그)
│   ├── sqs.tf               # skm-order-queue
│   ├── ecr.tf               # skm-order-processor 저장소
│   ├── iam.tf               # KEDA·앱·Karpenter 정책 + KarpenterNodeRole
│   └── {versions,variables,data,outputs}.tf
├── eksctl/
│   └── cluster.yaml         # skm-eks-cluster 1.35 + IRSA SA 3개 + tainted addon NG
├── k8s/                     # 번호 순 apply
│   ├── 00-namespace.yaml
│   ├── 10-karpenter-nodepool.yaml
│   ├── 20-deployment.yaml
│   └── 30-keda-scaledobject.yaml
└── README.md

# 앱 소스: task-2/provided/module-3/{app.py,Dockerfile,requirements.txt} (제공 원본, 수정 금지)
# 채점: task-2/mark/mark3-2026-08-01.sh (CloudShell, ap-northeast-2)
```

## 배포 순서

본 PC 단계는 이 모듈 **전용 PowerShell 탭**에서 진행하고, 시작 시 kubeconfig를 모듈 경로로 고정한다.
클러스터가 2개인 과제이므로(module-4: ap-northeast-1) 터미널 1개 = 클러스터 1개 — 이 터미널의 eksctl·kubectl·helm은 skm-eks-cluster에만 붙는다.

```powershell
cd module-3-eks-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```powershell
$env:KUBECONFIG = "$PWD\kubeconfig"
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2 --kubeconfig $env:KUBECONFIG
```

### 1) [본 PC·PowerShell] Terraform (~3분)

```powershell
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] EKS 클러스터 생성 (~15분 — 3단계와 병렬 진행)

```powershell
cd ../eksctl
$ACCOUNT_ID = terraform -chdir=../terraform output -raw account_id
$VPC_ID     = terraform -chdir=../terraform output -raw vpc_id
$SN = terraform -chdir=../terraform output -json private_subnet_ids | ConvertFrom-Json
# .Replace() 는 빈 값도 그대로 치환해 가드를 통과시키므로 치환 전 비어있음 검사 필수
if (!$ACCOUNT_ID -or !$VPC_ID -or !$SN.'skm-eks-sn-priv-a' -or !$SN.'skm-eks-sn-priv-c') { throw "terraform output 값 누락" }
$Y = Get-Content cluster.yaml -Raw
$Y = $Y.Replace('${ACCOUNT_ID}', $ACCOUNT_ID).Replace('${VPC_ID}', $VPC_ID)
$Y = $Y.Replace('${PRIV_SUBNET_A}', $SN.'skm-eks-sn-priv-a').Replace('${PRIV_SUBNET_C}', $SN.'skm-eks-sn-priv-c')
$Y | Set-Content cluster.rendered.yaml
if (Select-String -Pattern '\$\{' cluster.rendered.yaml) { throw "미치환 값 존재" }
eksctl create cluster -f cluster.rendered.yaml   # kubeconfig 는 $env:KUBECONFIG(모듈 경로)에 기록됨
```

### 3) [CloudShell — 2단계 대기 중 병렬] 이미지 빌드 & ECR push

`provided/module-3/{app.py,Dockerfile,requirements.txt}` 를 CloudShell 에 업로드(Actions → Upload file) 후:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin $ECR
docker build -t $ECR/skm-order-processor:latest .
docker push $ECR/skm-order-processor:latest
```

### 4) [본 PC·PowerShell] KEDA 설치 (keda 네임스페이스)

```powershell
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.20.1 `
  --set serviceAccount.operator.create=false --set serviceAccount.operator.name=keda-operator `
  --set-json 'tolerations=[{"key":"CriticalAddonsOnly","operator":"Exists"}]'
kubectl get pods -n keda    # operator·metrics·webhooks 3개 모두 Running 확인
```

### 5) [본 PC·PowerShell] Karpenter 설치 (kube-system)

```powershell
# replicas=1 필수: chart 기본 2 + required anti-affinity 라 노드 1대(addon NG 1/1/1)에선 --wait 가 영원히 대기
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.14.0 -n kube-system `
  --set replicas=1 `
  --set serviceAccount.create=false --set serviceAccount.name=karpenter `
  --set settings.clusterName=skm-eks-cluster --set settings.interruptionQueue="" `
  --set controller.resources.requests.cpu=500m --set controller.resources.requests.memory=512Mi `
  --wait
```

### 6) [본 PC·PowerShell] k8s 리소스 apply (번호 순)

```powershell
cd ../k8s
$SQS_URL = terraform -chdir=../terraform output -raw sqs_queue_url
$ECR_URL = terraform -chdir=../terraform output -raw ecr_repository_url
if (!$SQS_URL -or !$ECR_URL) { throw "terraform output 값 누락" }
$ECR_IMAGE = "$($ECR_URL):latest"
New-Item -ItemType Directory -Force rendered | Out-Null
Get-ChildItem *.yaml | ForEach-Object {
  (Get-Content $_ -Raw).Replace('${ECR_IMAGE}', $ECR_IMAGE).Replace('${SQS_URL}', $SQS_URL) | Set-Content "rendered/$($_.Name)"
}
if (Select-String -Pattern '\$\{' rendered\*.yaml) { throw "미치환 값 존재" }
kubectl apply -f rendered/    # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장
```

앱 Pod 가 Karpenter 노드에서 Running 될 때까지 대기 (노드 프로비저닝 ~2분):

```powershell
kubectl get pod -n skillsmkt -o wide -w
```

### 7) [CloudShell] 클러스터 접속 확인

```bash
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2
kubectl get nodes
```

컨텍스트 설정에서 오류가 나면 **모듈당 1회에 한해** `rm -rf ~/.kube/` 로 초기화한 뒤 다시 실행할 수 있다(유의사항 18) — kubeconfig 에 cluster info 가 이미 있으면 덮어쓰지 않는 동작이 원인이다.

`Unauthorized` 가 나오면(채점 주체 ≠ 클러스터 생성자) CloudShell 의 IAM ARN 을 확인 후 본 PC 에서 access entry 를 추가한다:

```bash
aws sts get-caller-identity --query Arn --output text   # CloudShell 에서 ARN 확인
```

```powershell
aws eks create-access-entry --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-2
aws eks associate-access-policy --cluster-name skm-eks-cluster --principal-arn <CLOUDSHELL_IAM_ARN> `
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster --region ap-northeast-2
```

### 8) [CloudShell] 셀프 채점 (3-6·3-7 스케일 테스트로 ~5분 소요)

사전 상태 확인: 앱 Pod 1개, Karpenter 노드 1대, 큐 비어 있음.

```bash
kubectl get deploy order-processor -n skillsmkt
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool
bash mark/mark3-2026-08-01.sh   # 2026-08-01 정정본 (3-6 대기 150초). 원본은 mark3.sh
```

## Teardown

### [본 PC·PowerShell]

```powershell
cd k8s
kubectl delete -f rendered/30-keda-scaledobject.yaml
kubectl delete -f rendered/20-deployment.yaml
kubectl delete -f rendered/10-karpenter-nodepool.yaml   # Karpenter 노드 드레인·종료 대기 (~2분)
cd ../eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
