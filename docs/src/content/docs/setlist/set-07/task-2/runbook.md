---
title: 배포 런북
description: 7세트 2과제 모듈별 배포·채점·teardown 절차
sidebar:
  order: 2
---

모듈은 서로 독립이라 순서 없이 배포한다. 본 PC 단계는 **PowerShell 7 기준**(대회 환경 Windows 11), 채점은 CloudShell(bash). 저장소 `set-07/task-2/` 각 모듈 README와 동일한 절차이며, 본 PC가 Linux면 각 모듈의 README.linux.md를 따른다.

## 모듈 1 — NoSQL (ap-southeast-1)

### 1) [본 PC·PowerShell] 배포

```powershell
cd set-07/task-2/module-1-nosql/terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] 앱 기동 대기 (부팅 + pip 설치 ~2-3분)

```powershell
$URL = terraform output -raw healthcheck_url
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 $URL) -ne "200") { Start-Sleep 10 }
```

### 3) [CloudShell] 셀프 채점 (1-6-A 는 sleep 30×2 로 약 70초 소요)

```bash
bash mark/mark1.sh
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-1-nosql/terraform
terraform destroy -auto-approve
```

## 모듈 2 — CDN Function (us-east-1)

### 1) [본 PC·PowerShell] 배포 (distribution 배포 대기 포함 ~5-7분)

```powershell
cd set-07/task-2/module-2-cdn-function/terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] A/B 동작 검증

```powershell
$URL = terraform output -raw landing_url
# 쿠키 강제: 해당 버전 본문 + Set-Cookie 없음이 기대 출력
curl.exe -si -b "x-sp-ab=a" $URL | Select-String "version-badge|set-cookie"
curl.exe -si -b "x-sp-ab=b" $URL | Select-String "version-badge|set-cookie"
# 첫 방문: Set-Cookie x-sp-ab=<a|b>; Path=/; Max-Age=86400 + 해당 버전 본문이 기대 출력
curl.exe -si $URL | Select-String "version-badge|set-cookie"
```

### 3) [CloudShell] 셀프 채점 (2-6-A 는 KVS 전파 대기로 최대 ~2분)

```bash
bash mark/mark2.sh
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-2-cdn-function/terraform
terraform destroy -auto-approve
```

## 모듈 3 — EKS Scaling (ap-northeast-2)

본 PC 단계는 이 모듈 **전용 PowerShell 탭**에서 진행하며, 시작 시 kubeconfig를 모듈 경로로 고정한다
(클러스터 2개 과제 — 터미널 1개 = 클러스터 1개). 재부팅 후엔 같은 두 줄 + `aws eks update-kubeconfig --kubeconfig $env:KUBECONFIG`로 복구.

```powershell
cd set-07/task-2/module-3-eks-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"
```

### 1) [본 PC·PowerShell] Terraform (~3분)

```powershell
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] EKS 클러스터 생성 (~15분 — 3단계와 병렬)

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

### 3) [CloudShell — 2단계 대기 중 병렬] 이미지 빌드 & ECR push

`provided/module-3/{app.py,Dockerfile,requirements.txt}` 업로드 후:

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
kubectl get pods -n keda    # 3개 모두 Running 확인
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
kubectl get pod -n skillsmkt -o wide -w    # Karpenter 노드에서 Running 까지 ~2분
```

### 7) [CloudShell] 접속 확인 + 셀프 채점 (3-6·3-7 스케일 테스트로 ~5분)

```bash
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2
kubectl get nodes    # Unauthorized 시 모듈 README 7단계 access entry fallback
bash mark/mark3.sh   # 사전 상태: Pod 1개·Karpenter 노드 1대·빈 큐
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-3-eks-scaling/k8s
kubectl delete -f rendered/30-keda-scaledobject.yaml
kubectl delete -f rendered/20-deployment.yaml
kubectl delete -f rendered/10-karpenter-nodepool.yaml   # Karpenter 노드 종료 대기 ~2분
cd ../eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```

## 모듈 4 — Container Logging (ap-northeast-1)

본 PC 단계는 이 모듈 **전용 PowerShell 탭**에서 진행하며, 시작 시 kubeconfig를 모듈 경로로 고정한다
(터미널 1개 = 클러스터 1개 — 모듈 3, 그리고 3과제의 EKS와 같은 원칙). 재부팅 후엔 같은 줄 + `aws eks update-kubeconfig --kubeconfig $env:KUBECONFIG`로 복구.

```powershell
cd set-07/task-2/module-4-container-logging
$env:KUBECONFIG = "$PWD\kubeconfig"
$PLAYER = "01"   # 선수 등번호
```

### 0) [본 PC·PowerShell] IAM 권한 조기 검증

지급 계정(PowerUser급 IAM)이 Role을 만들 수 있는지 확인한다. AccessDenied면 즉시 감독 문의:

```powershell
aws iam create-role --role-name perm-probe --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' | Out-Null
aws iam delete-role --role-name perm-probe
```

### 1) [본 PC·PowerShell] Terraform (~3분, TG는 7단계 전까지 unhealthy가 정상)

```powershell
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] EKS 클러스터 생성 (~15분 — 3단계와 병렬)

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```powershell
cd ../eksctl
$ACCOUNT_ID = terraform -chdir=../terraform output -raw account_id
$VPC_ID     = terraform -chdir=../terraform output -raw vpc_id
$SN = terraform -chdir=../terraform output -json private_subnet_ids | ConvertFrom-Json
if (!$ACCOUNT_ID -or !$VPC_ID -or !$SN.'o11y-sn-priv-a' -or !$SN.'o11y-sn-priv-c') { throw "terraform output 값 누락" }
[pscustomobject]@{ACCOUNT_ID=$ACCOUNT_ID; VPC_ID=$VPC_ID; SUBNET_A=$SN.'o11y-sn-priv-a'; SUBNET_C=$SN.'o11y-sn-priv-c'} | Format-List
```

**② 치환**

```powershell
$Y = Get-Content cluster.yaml -Raw
$Y = $Y.Replace('${ACCOUNT_ID}', $ACCOUNT_ID).Replace('${VPC_ID}', $VPC_ID)
$Y = $Y.Replace('${PRIV_SUBNET_A}', $SN.'o11y-sn-priv-a').Replace('${PRIV_SUBNET_C}', $SN.'o11y-sn-priv-c')
$Y | Set-Content cluster.rendered.yaml
```

**③ 치환 확인** — 미치환 탐지 + 값 육안 확인

```powershell
if (Select-String -Pattern '\$\{' cluster.rendered.yaml) { throw "미치환 값 존재" }
Select-String -Pattern 'id:|arn:aws' cluster.rendered.yaml
```

**④ 적용**

```powershell
eksctl create cluster -f cluster.rendered.yaml
```

### 3) [CloudShell — 2단계 대기 중 병렬] 이미지 빌드 & ECR push

`provided/module-4/app.py` + `module-4-container-logging/app/Dockerfile`(**수정본 — 지급본은 flask 미설치**) 업로드 후:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR=$ACCOUNT_ID.dkr.ecr.ap-northeast-1.amazonaws.com
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $ECR
docker build -t $ECR/o11y-log-generator:latest .
docker push $ECR/o11y-log-generator:latest
```

### 4) [본 PC·PowerShell] 노드 검증 (zone 2종·KST)

```powershell
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | Sort-Object -Unique
kubectl debug node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=busybox -- chroot /host date
```

### 5) [본 PC·PowerShell] k8s 렌더 + 네임스페이스·StorageClass apply

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```powershell
cd ../k8s
$ECR_URL   = terraform -chdir=../terraform output -raw ecr_repository_url
$ALB_SG_ID = terraform -chdir=../terraform output -raw alb_sg_id
if (!$ECR_URL -or !$ALB_SG_ID) { throw "terraform output 값 누락" }
$ECR_IMAGE = "$($ECR_URL):latest"
[pscustomobject]@{ECR_IMAGE=$ECR_IMAGE; ALB_SG_ID=$ALB_SG_ID} | Format-List
```

**② 치환**

```powershell
New-Item -ItemType Directory -Force rendered | Out-Null
Get-ChildItem *.yaml | ForEach-Object {
  (Get-Content $_ -Raw).Replace('${ECR_IMAGE}', $ECR_IMAGE).Replace('${ALB_SG_ID}', $ALB_SG_ID) | Set-Content "rendered/$($_.Name)"
}
```

**③ 치환 확인**

```powershell
if (Select-String -Pattern '\$\{' rendered\*.yaml) { throw "미치환 값 존재" }
Select-String -Pattern 'image:|groupID:' rendered\*.yaml
```

**④ 적용** — 05-storageclass 는 6단계 Loki PVC 의 전제라 helm 보다 먼저 있어야 한다

```powershell
kubectl apply -f rendered/00-namespace.yaml -f rendered/05-storageclass.yaml
kubectl get sc o11y-gp3
```

### 6) [본 PC·PowerShell] helm 설치 (LBC → Loki → Grafana)

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

$VPC_ID = terraform -chdir=../terraform output -raw vpc_id
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.4.3 `
  --set clusterName=o11y-cluster --set region=ap-northeast-1 --set vpcId=$VPC_ID `
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --wait

helm upgrade --install o11y-loki grafana-community/loki -n monitoring --version 18.7.1 -f ../helm/loki-values.yaml --wait

helm upgrade --install o11y-grafana grafana-community/grafana -n monitoring --version 12.10.0 -f ../helm/grafana-values.yaml `
  --set adminUser="skills$PLAYER" --set adminPassword="GoodJob!Skills$PLAYER^^" `
  --set-file dashboards.default.log-overview.json=../helm/dashboards/log-overview.json --wait
```

### 7) [본 PC·PowerShell] k8s 리소스 apply + TG healthy 확인

```powershell
kubectl apply -f rendered/    # 00·05는 재적용(무해), TGB CRD 는 6단계 LBC 가 제공
foreach ($tg in 'o11y-app-tg','o11y-grafana-tg') {
  aws elbv2 describe-target-health --target-group-arn (aws elbv2 describe-target-groups --names $tg --query 'TargetGroups[0].TargetGroupArn' --output text --region ap-northeast-1) --query 'TargetHealthDescriptions[].TargetHealth.State' --output text --region ap-northeast-1
}
# 기대: healthy healthy / healthy (pod Ready 후 1~2분)
```

### 8) [본 PC·PowerShell] 종단 스모크 (ALB → Loki → Grafana)

```powershell
$APP_ALB = terraform -chdir=../terraform output -raw app_alb_dns
curl.exe -s "http://$APP_ALB/healthz"                   # {"status":"ok"}
curl.exe -s "http://$APP_ALB/log?level=error&count=3"   # {"generated":3,"level":"error"}
# 별도 탭: kubectl port-forward -n monitoring svc/o11y-loki 3100:3100
curl.exe -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' --data-urlencode 'limit=5'
```

Grafana ALB 접속 → `skills<등번호>` 로그인 → Log Overview 3패널·plain 범례 + Data Sources → Loki → Save & Test.

### 9) [CloudShell] 접속 확인 + 셀프 채점

```bash
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1
kubectl get nodes    # Unauthorized 시 모듈 README 9단계 access entry fallback
bash mark/mark4.sh   # 4-5·4-6 은 수동 채점 — 스크립트는 4-1~4-4 자동
```

### Teardown [본 PC·PowerShell]

```powershell
cd set-07/task-2/module-4-container-logging/k8s
kubectl delete -f rendered/40-tgb-grafana.yaml
kubectl delete -f rendered/30-tgb-app.yaml
helm uninstall o11y-grafana -n monitoring
helm uninstall o11y-loki -n monitoring
kubectl delete pvc -n monitoring --all   # StatefulSet PVC 잔존 — EBS 고아 볼륨 방지
helm uninstall aws-load-balancer-controller -n kube-system
cd ../eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
