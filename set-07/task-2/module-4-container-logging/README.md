# Module 4 — Container Logging (ap-northeast-1)

EKS 1.35(Multi-AZ·KST 노드) + ECR 이미지 앱 + OTel Collector(DaemonSet) + Loki(Single Binary·PV) + Grafana, ALB 2대(고정 이름 TG) 노출. 채점은 CloudShell에서 `mark/mark4.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-4-container-logging/
├── app/
│   └── Dockerfile               # 지급본의 2026-08-01 정정 반영본 (Flask==3.1.3 설치)
├── terraform/
│   ├── vpc.tf                   # 자체 VPC + pub/priv 서브넷(1a/1c) + NAT
│   ├── ecr.tf                   # o11y-log-generator 저장소
│   ├── iam.tf                   # LBC IRSA 정책 (files/lbc-iam-policy.json)
│   ├── alb.tf                   # ALB 2 + TG 2(ip type) + 공유 SG + listener
│   └── {versions,variables,data,outputs}.tf
├── eksctl/
│   └── cluster.yaml             # o11y-cluster 1.35 + LBC IRSA SA + EBS CSI addon + KST NG
├── helm/
│   ├── loki-values.yaml         # Single Binary + PV + OTLP
│   ├── grafana-values.yaml      # datasource·dashboard provisioning
│   └── dashboards/log-overview.json
├── k8s/                         # 번호 순 apply (rendered/ 로 치환 후)
│   ├── 00-namespace.yaml
│   ├── 05-storageclass.yaml
│   ├── 10-app.yaml
│   ├── 20-otel-collector.yaml
│   ├── 30-tgb-app.yaml
│   └── 40-tgb-grafana.yaml
└── README.md

# 앱 소스: task-2/provided/module-4/app.py (제공 원본, 수정 금지 — Dockerfile 은 app/ 수정본 사용)
# 채점: task-2/mark/mark4.sh (CloudShell, ap-northeast-1)
```

## 배포 순서

본 PC 단계는 이 모듈 **전용 PowerShell 탭**에서 진행하고, 시작 시 kubeconfig를 모듈 경로로 고정한다.
EKS 클러스터가 여러 개인 대회이므로(module-3: ap-northeast-2, 3과제도 EKS) 터미널 1개 = 클러스터 1개 — 이 터미널의 eksctl·kubectl·helm은 o11y-cluster에만 붙는다.

```powershell
cd module-4-container-logging
$env:KUBECONFIG = "$PWD\kubeconfig"
$PLAYER = "01"   # 선수 등번호 (Grafana admin 계정에 사용)
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```powershell
$env:KUBECONFIG = "$PWD\kubeconfig"
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1 --kubeconfig $env:KUBECONFIG
```

### 0) [본 PC·PowerShell] IAM 권한 조기 검증

지급 계정은 PowerUser급 IAM 계정 — eksctl·IRSA 는 IAM Role 생성 권한이 전제다. 시작 전에 확인하고, AccessDenied 면 즉시 감독에게 문의한다:

```powershell
aws iam create-role --role-name perm-probe --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' | Out-Null
aws iam delete-role --role-name perm-probe
```

### 1) [본 PC·PowerShell] Terraform (~3분)

ALB·TG 는 pod 등록(7단계) 전까지 unhealthy — 정상이다.

```powershell
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] EKS 클러스터 생성 (~15분 — 3단계와 병렬 진행)

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```powershell
cd ../eksctl
$ACCOUNT_ID = terraform -chdir=../terraform output -raw account_id
$VPC_ID     = terraform -chdir=../terraform output -raw vpc_id
$SN = terraform -chdir=../terraform output -json private_subnet_ids | ConvertFrom-Json
# .Replace() 는 빈 값도 그대로 치환해 가드를 통과시키므로 치환 전 비어있음 검사 필수
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
eksctl create cluster -f cluster.rendered.yaml   # kubeconfig 는 $env:KUBECONFIG(모듈 경로)에 기록됨
```

### 3) [CloudShell — 2단계 대기 중 병렬] 이미지 빌드 & ECR push

`provided/module-4/app.py` 와 `module-4-container-logging/app/Dockerfile` 을 CloudShell 에 업로드(Actions → Upload file) 후:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR=$ACCOUNT_ID.dkr.ecr.ap-northeast-1.amazonaws.com
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $ECR
docker build -t $ECR/o11y-log-generator:latest .
docker push $ECR/o11y-log-generator:latest
```

> 최초 지급 Dockerfile(provided/module-4/Dockerfile)이 아니라 **app/ 정정 반영본**을 쓴다. 최초 지급본은 flask 를 설치하지 않아 그대로 빌드하면 CrashLoopBackOff — 2026-08-01 정정으로 pip install 이 추가됐고 그 내용이 app/Dockerfile(= provided/module-4/Dockerfile-2026-08-01)이다.

### 4) [본 PC·PowerShell] 노드 검증 (채점 4-1)

```powershell
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | Sort-Object -Unique   # 1a·1c 두 줄
kubectl debug node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=busybox -- chroot /host date            # KST 확인
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
# region·vpcId 명시: IMDS 자동탐지(hop limit)로 인한 기동 실패 회피
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.4.3 `
  --set clusterName=o11y-cluster --set region=ap-northeast-1 --set vpcId=$VPC_ID `
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --wait

helm upgrade --install o11y-loki grafana-community/loki -n monitoring --version 18.7.1 -f ../helm/loki-values.yaml --wait

# PS7 은 큰따옴표 안의 ! ^^ 를 리터럴로 다룬다 (bash 와 달리 이스케이프 불필요)
helm upgrade --install o11y-grafana grafana-community/grafana -n monitoring --version 12.10.0 -f ../helm/grafana-values.yaml `
  --set adminUser="skills$PLAYER" --set adminPassword="GoodJob!Skills$PLAYER^^" `
  --set-file dashboards.default.log-overview.json=../helm/dashboards/log-overview.json --wait
```

### 7) [본 PC·PowerShell] k8s 리소스 apply (번호 순) + TG healthy 확인

```powershell
kubectl apply -f rendered/    # 00·05는 재적용(무해), TGB CRD 는 6단계 LBC 가 제공
kubectl get pods -n o11y
kubectl get pods -n monitoring
```

pod Ready 후 1~2분 내 TG 등록·healthy 전환 (채점 4-2 사전 확인):

```powershell
foreach ($tg in 'o11y-app-tg','o11y-grafana-tg') {
  aws elbv2 describe-target-health --target-group-arn (aws elbv2 describe-target-groups --names $tg --query 'TargetGroups[0].TargetGroupArn' --output text --region ap-northeast-1) --query 'TargetHealthDescriptions[].TargetHealth.State' --output text --region ap-northeast-1
}
# 기대: healthy healthy / healthy
```

### 8) [본 PC·PowerShell] 종단 스모크 (채점 4-4·4-5·4-6)

```powershell
$APP_ALB = terraform -chdir=../terraform output -raw app_alb_dns
curl.exe -s "http://$APP_ALB/healthz"                       # {"status":"ok"}
curl.exe -s "http://$APP_ALB/log?level=error&count=3"       # {"generated":3,"level":"error"}
# 대시보드 3색 범례(error 빨강·warn 노랑·info 초록) 확인용 — 레벨별 건수를 다르게
curl.exe -s "http://$APP_ALB/log?level=warn&count=10"
curl.exe -s "http://$APP_ALB/log?level=info&count=30"
```

Loki 적재 확인(별도 탭에서 port-forward 후):

```powershell
kubectl port-forward -n monitoring svc/o11y-loki 3100:3100
```

```powershell
curl.exe -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' --data-urlencode 'limit=5'
```

Grafana: `http://<grafana_alb_dns>` 접속 → `skills<등번호>` 로그인 → Log Overview 3패널(범례 plain text) + Connections → Data Sources → Loki → Save & Test.

> 대시보드 기본 구간이 `now-1h` 이고 앱은 요청 없이는 JSON 로그를 만들지 않는다. 접속 직전에 위 `/log` 호출을 해둬야 세 패널에 데이터가 찬다.

### 9) [CloudShell] 클러스터 접속 확인 + 셀프 채점

```bash
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1
kubectl get nodes
```

`Unauthorized` 가 나오면(채점 주체 ≠ 클러스터 생성자) CloudShell 의 IAM ARN 을 확인 후 본 PC 에서 access entry 를 추가한다:

```bash
aws sts get-caller-identity --query Arn --output text   # CloudShell 에서 ARN 확인
```

```powershell
aws eks create-access-entry --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-1
aws eks associate-access-policy --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> `
  --policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster --region ap-northeast-1
```

```bash
bash mark/mark4.sh
```

## Teardown

### [본 PC·PowerShell]

```powershell
cd k8s
kubectl delete -f rendered/40-tgb-grafana.yaml
kubectl delete -f rendered/30-tgb-app.yaml      # LBC 가 TG 타깃·SG 규칙 정리
helm uninstall o11y-grafana -n monitoring
helm uninstall o11y-loki -n monitoring
kubectl delete pvc -n monitoring --all          # StatefulSet PVC 는 uninstall 후 잔존 — EBS 고아 볼륨 방지
helm uninstall aws-load-balancer-controller -n kube-system
cd ../eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
