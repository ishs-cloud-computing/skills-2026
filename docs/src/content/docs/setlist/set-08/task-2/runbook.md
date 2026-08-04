---
title: 배포 런북
description: 8세트 2과제 모듈별 배포·채점·teardown 절차
sidebar:
  order: 2
---

모듈은 서로 독립이라 순서 없이 배포한다. 본 PC 단계는 **PowerShell 7 기준**(대회 환경 Windows 11), 채점은 CloudShell(bash). 저장소 `set-08/task-2/` 각 모듈 README와 동일한 절차이며, 본 PC가 Linux면 각 모듈의 README.linux.md를 따른다.

CloudShell 업로드 파일은 항상 `$HOME`에 평평하게 저장되고 리전별로 홈이 분리된다. 채점 스크립트(`mark/mark2-N.sh`)는 업로드 후 실행 전에 CRLF 가드를 거친다:

```bash
sed -i 's/\r$//' mark2-N.sh
```

## 모듈 1 — NoSQL DocumentDB (ap-northeast-2)

### 1) [본 PC·PowerShell] 배포 (실측 ~7분 — DocumentDB 인스턴스 생성이 병목)

```powershell
terraform -chdir=module-1-nosql/terraform init
terraform -chdir=module-1-nosql/terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] 앱 기동 대기 + 검증 (pip 설치 + seed/index 재시도 루프)

```powershell
$env:NOSQL_CLIENT_IP = terraform -chdir=module-1-nosql/terraform output -raw client_public_ip
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$($env:NOSQL_CLIENT_IP):8080/health") -ne "200") { Start-Sleep 15 }

curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/health"                        # → status ok, tls true
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/admin/summary"              # → orders 8 / products 6 / sessions 3
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/admin/indexes"              # → sessions.expiresAt: expireAfterSeconds 0
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/orders/O-1001"
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/customers/C001/orders"
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl.exe -s "http://$($env:NOSQL_CLIENT_IP):8080/v1/products/low-stock?warehouseId=W-A"
```

### 3) [CloudShell] 셀프 채점

```bash
bash mark2-1.sh
```

### Teardown [본 PC·PowerShell]

```powershell
terraform -chdir=module-1-nosql/terraform destroy -auto-approve
```

## 모듈 2 — VPC Lattice (ap-northeast-1)

### 1) [본 PC·PowerShell] 배포

```powershell
terraform -chdir=module-2-lattice/terraform init
terraform -chdir=module-2-lattice/terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] 검증 (user-data systemd 기동 대기 ~1-2분)

```powershell
$env:CLIENT_IP = terraform -chdir=module-2-lattice/terraform output -raw client_public_ip
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$env:CLIENT_IP/health") -ne "200") { Start-Sleep 10 }

# Lattice Target Group healthy 전환은 /health 통과 후 추가로 ~30-60초 걸릴 수 있어 재시도 루프로 흡수
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$env:CLIENT_IP/v1/client/orders?id=1001") -ne "200") { Start-Sleep 10 }

curl.exe -s "http://$env:CLIENT_IP/v1/client/orders?id=1001"
# → service.order_id=1001, service.via=vpc-lattice 확인
```

### 3) [CloudShell] 셀프 채점

```bash
bash mark2-2.sh
```

### Teardown [본 PC·PowerShell]

```powershell
terraform -chdir=module-2-lattice/terraform destroy -auto-approve
```

1회차가 EC2 삭제로 target이 `UNUSED`로 떨어지는 레이스로 실패할 수 있다(`TargetGroupNotInUse`). **같은 명령을 한 번 더 실행**하면 남은 attachment/target group이 정리된다.

## 모듈 3 — Cloud Event Handling (ap-southeast-1)

### 1) [본 PC·PowerShell] 배포

```powershell
terraform -chdir=module-3-event-handling/terraform init
terraform -chdir=module-3-event-handling/terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] 검증 1 — Lambda 직접 호출 (채점 3-5와 동일 payload)

```powershell
$env:PROTECTED_SG_ID = terraform -chdir=module-3-event-handling/terraform output -raw protected_sg_id

'{"detail":{"eventName":"AuthorizeSecurityGroupIngress","requestParameters":{"groupId":"' + $env:PROTECTED_SG_ID + '"}}}' |
  Set-Content -NoNewline payload.json
aws ec2 authorize-security-group-ingress --group-id $env:PROTECTED_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws lambda invoke --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file://payload.json out.json
Get-Content out.json                    # → status RESTORED, publishStatus SNS_PUBLISHED
aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "SecurityGroups[0].IpPermissions"   # → []
Remove-Item payload.json, out.json
```

### 3) [본 PC·PowerShell] 검증 2 — 실경로 (CloudTrail→EventBridge→Lambda, 실측 ~20초·최대 수 분)

```powershell
aws ec2 authorize-security-group-ingress --group-id $env:PROTECTED_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
while ((aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "length(SecurityGroups[0].IpPermissions)" --output text) -ne "0") { Start-Sleep 15 }
aws ec2 describe-security-groups --group-ids $env:PROTECTED_SG_ID --query "SecurityGroups[0].IpPermissions"   # → [] (180초 이내)
```

### 4) [CloudShell] 셀프 채점

```bash
bash mark2-3.sh
```

### Teardown [본 PC·PowerShell]

```powershell
terraform -chdir=module-3-event-handling/terraform destroy -auto-approve
```

## 모듈 4 — SQS Scaling (us-west-2)

본 PC 단계는 이 모듈 **전용 PowerShell 탭**에서 진행하며, 시작 시 kubeconfig를 모듈 경로로 고정한다(터미널 1개 = 클러스터 1개).

```powershell
cd module-4-sqs-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"
```

재부팅 후엔 같은 줄 + `aws eks update-kubeconfig --name skills-sqs-cluster --region us-west-2 --kubeconfig $env:KUBECONFIG`로 복구.

### 0) 시작 전 확인 (대회 시작 직후 1회)

CloudShell 접속을 확인한다 — 이 모듈은 로컬 Docker가 없어 3단계 이미지 build/push가 CloudShell 필수 경로다.

### 1) [본 PC·PowerShell] terraform apply

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] cluster.yaml 렌더링 + eksctl create (~19-20분 — 3단계와 병렬)

```powershell
$env:VPC_ID = terraform -chdir=terraform output -raw vpc_id
$SN = terraform -chdir=terraform output -json private_subnet_ids | ConvertFrom-Json
$env:PRIV_SUBNET_A = $SN.'skills-sqs-sn-priv-a'
$env:PRIV_SUBNET_B = $SN.'skills-sqs-sn-priv-b'
$env:KEDA_POLICY_ARN = terraform -chdir=terraform output -raw keda_policy_arn
$env:KARPENTER_POLICY_ARN = terraform -chdir=terraform output -raw karpenter_policy_arn
$env:WORKER_POLICY_ARN = terraform -chdir=terraform output -raw worker_policy_arn
$env:NODE_ROLE_ARN = terraform -chdir=terraform output -raw karpenter_node_role_arn
if (!$env:VPC_ID -or !$env:PRIV_SUBNET_A -or !$env:PRIV_SUBNET_B -or !$env:KEDA_POLICY_ARN -or !$env:KARPENTER_POLICY_ARN -or !$env:WORKER_POLICY_ARN -or !$env:NODE_ROLE_ARN) { throw "STOP: terraform output 값 누락" }

New-Item -ItemType Directory -Force eksctl/rendered | Out-Null
$Y = Get-Content eksctl/cluster.yaml -Raw
$Y = $Y.Replace('${VPC_ID}', $env:VPC_ID).Replace('${PRIV_SUBNET_A}', $env:PRIV_SUBNET_A).Replace('${PRIV_SUBNET_B}', $env:PRIV_SUBNET_B)
$Y = $Y.Replace('${KEDA_POLICY_ARN}', $env:KEDA_POLICY_ARN).Replace('${KARPENTER_POLICY_ARN}', $env:KARPENTER_POLICY_ARN)
$Y = $Y.Replace('${WORKER_POLICY_ARN}', $env:WORKER_POLICY_ARN).Replace('${NODE_ROLE_ARN}', $env:NODE_ROLE_ARN)
$Y | Set-Content eksctl/rendered/cluster.yaml
if (Select-String -Path eksctl/rendered/cluster.yaml -Pattern '\$\{') { throw "STOP: 미치환 값 존재" }

eksctl create cluster -f eksctl/rendered/cluster.yaml
```

도구·셸 타임아웃(보통 10분)을 넘기므로 별도 창에 detach 실행하고 로그 파일로 진행을 확인해도 된다:

```powershell
Start-Process pwsh -ArgumentList "-NoProfile","-Command","`$env:KUBECONFIG='$PWD\kubeconfig'; eksctl create cluster -f eksctl/rendered/cluster.yaml" -RedirectStandardOutput eksctl.log -RedirectStandardError eksctl.err -WindowStyle Hidden
Get-Content eksctl.log -Tail 5   # "is ready" 나오면 완료
```

### 3) [CloudShell — 2단계 대기 중 병렬] worker 이미지 build/push

`app/Dockerfile`, `provided/module-4/worker.py`, `.env` 업로드 후(**us-west-2 CloudShell**):

```bash
mkdir -p ~/module4-build && cd ~/module4-build
cp ~/Dockerfile ~/worker.py ~/.env .
sed -i 's/\r$//' .env
source .env
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t "${ECR_IMAGE}" .
docker push "${ECR_IMAGE}"
```

### 4) [본 PC·PowerShell] helm — Karpenter·KEDA (버전 미핀: 최신 안정)

```powershell
helm install karpenter oci://public.ecr.aws/karpenter/karpenter -n karpenter `
  --set settings.clusterName=skills-sqs-cluster `
  --set serviceAccount.create=false --set serviceAccount.name=karpenter `
  --set replicas=1 --set dnsPolicy=Default --wait

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda -n keda `
  --set serviceAccount.operator.create=false --set serviceAccount.operator.name=keda-operator --wait

kubectl get pods -n karpenter
kubectl get pods -n keda
```

### 5) [본 PC·PowerShell] k8s manifest 렌더링 + apply

```powershell
$env:ECR_IMAGE = "$(terraform -chdir=terraform output -raw ecr_repo_url):latest"
$env:QUEUE_URL = terraform -chdir=terraform output -raw queue_url
$env:REGION = "us-west-2"
$env:NODE_ROLE_NAME = terraform -chdir=terraform output -raw karpenter_node_role_name
if (!$env:ECR_IMAGE -or !$env:QUEUE_URL -or !$env:NODE_ROLE_NAME) { throw "STOP: terraform output 값 누락" }

New-Item -ItemType Directory -Force k8s/rendered | Out-Null
Get-ChildItem k8s/*.yaml | ForEach-Object {
  (Get-Content $_ -Raw).Replace('${ECR_IMAGE}', $env:ECR_IMAGE).Replace('${QUEUE_URL}', $env:QUEUE_URL).Replace('${REGION}', $env:REGION).Replace('${NODE_ROLE_NAME}', $env:NODE_ROLE_NAME) | Set-Content "k8s/rendered/$($_.Name)"
}
if (Select-String -Pattern '\$\{' k8s/rendered/*.yaml) { throw "STOP: 미치환 값 존재" }
kubectl apply -f k8s/rendered/   # 파일명 알파벳 순 apply → 번호 prefix 가 순서 보장

kubectl get scaledobject,triggerauthentication -n skills-sqs
kubectl get nodepool,ec2nodeclass
```

큐가 비어 있으면 `minReplicaCount 0`이라 pod 0개가 정상이다.

### 6) [본 PC·PowerShell] 스케일 검증 (mark2-4.sh 4-6 시나리오 수동 재현)

```powershell
1..12 | ForEach-Object { aws sqs send-message --region us-west-2 --queue-url $env:QUEUE_URL --message-body "verify-$_" | Out-Null }

foreach ($t in 60, 120, 180) {
  Start-Sleep -Seconds 60
  kubectl get deployment sqs-worker -n skills-sqs
  kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
  kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
}
```

`ApproximateNumberOfMessages=0` 확인 후 90초 대기, pod 0·노드 0 복귀 확인.

### 7) [CloudShell] kubectl 접속 확인 + 셀프 채점 (mark2-4.sh 실측 ~11분)

```bash
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes   # Unauthorized 시 아래 access entry fallback
bash mark2-4.sh
```

`Unauthorized`면 CloudShell의 ARN을 확인 후 본 PC에서 access entry를 추가한다:

```bash
aws sts get-caller-identity --query Arn --output text
```

```powershell
aws eks create-access-entry --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region us-west-2
aws eks associate-access-policy --cluster-name skills-sqs-cluster --principal-arn <CLOUDSHELL_IAM_ARN> `
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster --region us-west-2
```

### Teardown [본 PC·PowerShell]

```powershell
kubectl delete -f k8s/rendered/ --wait=false
helm uninstall keda -n keda
helm uninstall karpenter -n karpenter
eksctl delete cluster -f eksctl/rendered/cluster.yaml
terraform -chdir=terraform destroy -auto-approve
```

`--wait=false`가 없으면 kubectl이 삭제 메시지 출력 후에도 종료되지 않고 매달린다(실측 15분+). `eksctl delete cluster`는 실측 약 8분(Fargate profile 3개 순차 삭제).
