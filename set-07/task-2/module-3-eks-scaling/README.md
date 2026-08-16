# Module 3 — EKS Scaling (ap-northeast-2)

SQS 주문 큐 + EKS 1.35(tainted Addon NG) + ECR 이미지 앱 + KEDA(Pod 스케일링) + Karpenter(노드 스케일링).
본 PC 는 `terraform` 과 `eksctl` 만 쓰고, 이미지 빌드·helm·kubectl·검증·채점은 전부 CloudShell(ap-northeast-2)에서 한다.
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
├── k8s/                     # 번호 순 apply (CloudShell 에서 rendered/ 로 치환)
│   ├── 00-namespace.yaml
│   ├── 10-karpenter-nodepool.yaml
│   ├── 20-deployment.yaml
│   └── 30-keda-scaledobject.yaml
├── cs-deploy.sh             # CloudShell: helm 설치 + KEDA·Karpenter + 치환·apply
└── README.md

# 앱 소스: task-2/provided/module-3/{app.py,Dockerfile,requirements.txt} (제공 원본, 수정 금지)
# 채점: task-2/mark/mark3-2026-08-01.sh (CloudShell, ap-northeast-2)
```

## 배포 순서

본 PC 단계(1·2)는 이 모듈 **전용 PowerShell 탭**에서 진행하고, 시작 시 kubeconfig를 모듈 경로로 고정한다.
클러스터가 2개인 과제이므로(module-4: ap-northeast-1) 터미널 1개 = 클러스터 1개 — 이 터미널의 eksctl 은 skm-eks-cluster 에만 붙는다.
CloudShell 쪽은 홈이 리전별로 갈려 있어 격리가 자동으로 된다(이 모듈은 ap-northeast-2 CloudShell).

### 0) [본 PC·PowerShell] 준비 — 터미널 고정 + CloudShell 전송 zip

```powershell
cd module-3-eks-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"   # eksctl 전용 (kubectl 은 CloudShell 에서 쓴다)
Compress-Archive -Force -DestinationPath "$env:TEMP\m3.zip" `
  -Path k8s, cs-deploy.sh, ..\provided\module-3\*, ..\mark\mark3-2026-08-01.sh
```

재부팅·새 터미널에서 복구:

```powershell
$env:KUBECONFIG = "$PWD\kubeconfig"
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
eksctl create cluster -f cluster.rendered.yaml
```

### 3) [CloudShell — 2단계 대기 중 병렬] 전송 + 이미지 빌드 & ECR push

ap-northeast-2 CloudShell 에서 `m3.zip` 을 업로드(작업 → 파일 업로드)한다. 저장소가 private 이라 `git clone` 은 쓰지 않는다.
업로드 파일은 `$HOME` 에 평평하게 저장된다.

```bash
mkdir -p ~/m3 && unzip -o ~/m3.zip -d ~/m3 && cd ~/m3
find . -name '*.sh' -exec sed -i 's/\r$//' {} +   # Windows 업로드 CRLF 가드 (멱등)
mkdir -p build && cp Dockerfile app.py requirements.txt build/
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR=$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "$ECR"
docker build -t "${ECR}/skm-order-processor:latest" build/
docker push "${ECR}/skm-order-processor:latest"
```

### 4) [CloudShell] 클러스터 접속 확인 — 채점과 같은 경로

여기서 막히면 이후 단계가 전부 막히고 k8s 채점 항목도 통째로 날아간다. 2단계가 끝나면 바로 확인한다.

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

### 5) [CloudShell] KEDA·Karpenter·k8s 배포

`cs-deploy.sh` 가 helm 설치(`$HOME/bin`) → SQS·ECR 값 조회 → 매니페스트 치환까지 하고 멈춘다. 값을 확인한 뒤 `--apply` 로 적용한다.

```bash
cd ~/m3
bash cs-deploy.sh            # 조회값 출력 후 종료 (적용 안 함)
```

```bash
bash cs-deploy.sh --apply    # KEDA 2.20.1 → Karpenter 1.14.0 → kubectl apply
```

세션이 끊겼다 돌아오면 `source ~/m3.env` 로 PATH·값을 복구한다.

### 6) [CloudShell] 검증 + 셀프 채점 (3-6·3-7 스케일 테스트로 ~5분 소요)

```bash
cd ~/m3
kubectl get pods -n keda                                      # operator·metrics·webhooks 3개 Running
kubectl get pod -n skillsmkt -o wide                          # Karpenter 노드에서 Running (프로비저닝 ~2분)
kubectl get deploy order-processor -n skillsmkt               # 사전 상태: 앱 Pod 1개
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool   # 사전 상태: 노드 1대
bash mark3-2026-08-01.sh   # 2026-08-01 정정본 (3-6 대기 150초). 원본은 mark3.sh
```

## Teardown

### [CloudShell]

```bash
cd ~/m3
kubectl delete -f k8s/rendered/30-keda-scaledobject.yaml
kubectl delete -f k8s/rendered/20-deployment.yaml
kubectl delete -f k8s/rendered/10-karpenter-nodepool.yaml   # Karpenter 노드 드레인·종료 대기 (~2분)
```

### [본 PC·PowerShell]

```powershell
cd eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
