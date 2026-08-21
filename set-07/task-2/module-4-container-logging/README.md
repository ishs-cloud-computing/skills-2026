# Module 4 — Container Logging (ap-northeast-1)

EKS 1.35(Multi-AZ·KST 노드) + ECR 이미지 앱 + OTel Collector(DaemonSet) + Loki(Single Binary·PV) + Grafana, ALB 2대(고정 이름 TG) 노출.
본 PC 는 `terraform` 과 `eksctl` 만 쓰고, 이미지 빌드·helm·kubectl·검증·스모크·채점은 전부 CloudShell(ap-northeast-1)에서 한다.
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
├── k8s/                         # 번호 순 apply (CloudShell 에서 rendered/ 로 치환)
│   ├── 00-namespace.yaml
│   ├── 05-storageclass.yaml
│   ├── 10-app.yaml
│   ├── 20-otel-collector.yaml
│   ├── 30-tgb-app.yaml
│   └── 40-tgb-grafana.yaml
├── cs-deploy.sh                 # CloudShell: helm 설치 + LBC·Loki·Grafana + 치환·apply
└── README.md

# 앱 소스: task-2/provided/module-4/app.py (제공 원본, 수정 금지 — Dockerfile 은 app/ 수정본 사용)
# 채점: task-2/mark/mark4-2026-08-04.sh (CloudShell, ap-northeast-1)
```

## 배포 순서

본 PC 단계(1·2)는 이 모듈 **전용 PowerShell 탭**에서 진행하고, 시작 시 kubeconfig를 모듈 경로로 고정한다.
EKS 클러스터가 여러 개인 대회이므로(module-3: ap-northeast-2, 3과제도 EKS) 터미널 1개 = 클러스터 1개 — 이 터미널의 eksctl 은 o11y-cluster 에만 붙는다.
CloudShell 쪽은 홈이 리전별로 갈려 있어 격리가 자동으로 된다(이 모듈은 ap-northeast-1 CloudShell).
### 0) [CloudShell] IAM 권한 조기 검증

지급 계정은 PowerUser급 IAM 계정 — eksctl·IRSA 는 IAM Role 생성 권한이 전제다. 시작 전에 확인하고, AccessDenied 면 즉시 감독에게 문의한다:

```bash
aws iam create-role --role-name perm-probe --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /dev/null \
  && aws iam delete-role --role-name perm-probe \
  || echo "STOP: IAM Role 생성 불가 — 감독 문의"
```

### 1) [본 PC·PowerShell] 준비 + Terraform (~3분)

ALB·TG 는 pod 등록(6단계) 전까지 unhealthy — 정상이다.

```powershell
cd module-4-container-logging
$env:KUBECONFIG = "$PWD\kubeconfig"   # eksctl 전용 (kubectl 은 CloudShell 에서 쓴다)
Compress-Archive -Force -DestinationPath m4.zip `
  -Path k8s, helm, cs-deploy.sh, app\Dockerfile, ..\provided\module-4\app.py, ..\mark\mark4-2026-08-04.sh
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC·PowerShell] EKS 클러스터 생성 (~15분 — 3단계와 병렬 진행)

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```powershell
# 1단계에 이어서 실행 (cwd = module-4-container-logging/terraform)
# PS7 은 -chdir=<path> 를 온전히 전달하지 못한다 — terraform 디렉터리 안에서 직접 조회한다
$ACCOUNT_ID = terraform output -raw account_id
$VPC_ID     = terraform output -raw vpc_id
$SN = terraform output -json private_subnet_ids | ConvertFrom-Json
# .Replace() 는 빈 값도 그대로 치환해 가드를 통과시키므로 치환 전 비어있음 검사 필수
if (!$ACCOUNT_ID -or !$VPC_ID -or !$SN.'o11y-sn-priv-a' -or !$SN.'o11y-sn-priv-c') { throw "terraform output 값 누락" }
[pscustomobject]@{ACCOUNT_ID=$ACCOUNT_ID; VPC_ID=$VPC_ID; SUBNET_A=$SN.'o11y-sn-priv-a'; SUBNET_C=$SN.'o11y-sn-priv-c'} | Format-List
cd ../eksctl
```

**② 치환**

```powershell
# Get-Content/Set-Content 기본 인코딩은 PowerShell 버전마다 달라 cluster.yaml 의 한글 주석이
# 깨질 수 있다(윈도우 PowerShell 5.1은 BOM 없는 파일을 시스템 ANSI로 읽는다) — 읽기·쓰기 인코딩을 명시한다.
$Y = Get-Content cluster.yaml -Raw -Encoding UTF8
$Y = $Y.Replace('${ACCOUNT_ID}', $ACCOUNT_ID).Replace('${VPC_ID}', $VPC_ID)
$Y = $Y.Replace('${PRIV_SUBNET_A}', $SN.'o11y-sn-priv-a').Replace('${PRIV_SUBNET_C}', $SN.'o11y-sn-priv-c')
[System.IO.File]::WriteAllText((Join-Path $PWD 'cluster.rendered.yaml'), $Y, [System.Text.UTF8Encoding]::new($false))
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

### 3) [CloudShell — 2단계 대기 중 병렬] 전송 + 이미지 빌드 & ECR push

ap-northeast-1 CloudShell 에서 `m4.zip` 을 업로드(작업 → 파일 업로드)한다. 저장소가 private 이라 `git clone` 은 쓰지 않는다.
업로드 파일은 `$HOME` 에 평평하게 저장된다.

```bash
mkdir -p ~/m4 && unzip -o ~/m4.zip -d ~/m4 && cd ~/m4
find . -name '*.sh' -exec sed -i 's/\r$//' {} +   # Windows 업로드 CRLF 가드 (멱등)
mkdir -p build && cp Dockerfile app.py build/
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR=$ACCOUNT_ID.dkr.ecr.ap-northeast-1.amazonaws.com
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin "$ECR"
docker build -t "${ECR}/o11y-log-generator:latest" build/
docker push "${ECR}/o11y-log-generator:latest"
```

> 최초 지급 Dockerfile(provided/module-4/Dockerfile)이 아니라 **app/ 정정 반영본**을 쓴다(zip 에 담기는 쪽이 그것이다). 최초 지급본은 flask 를 설치하지 않아 그대로 빌드하면 CrashLoopBackOff — 2026-08-01 정정으로 pip install 이 추가됐고 그 내용이 app/Dockerfile(= provided/module-4/Dockerfile-2026-08-01)이다.

### 4) [CloudShell] 클러스터 접속 확인 + 노드 검증 (채점 4-1)

접속이 막히면 이후 단계가 전부 막히고 k8s 채점 항목도 통째로 날아간다. 2단계가 끝나면 바로 확인한다.

```bash
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1
kubectl get nodes
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -u   # 1a·1c 두 줄
kubectl debug node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=busybox -- chroot /host date  # KST 확인
```

컨텍스트 설정에서 오류가 나면 **모듈당 1회에 한해** `rm -rf ~/.kube/` 로 초기화한 뒤 다시 실행할 수 있다(유의사항 18) — kubeconfig 에 cluster info 가 이미 있으면 덮어쓰지 않는 동작이 원인이다.

`Unauthorized` 가 나오면(채점 주체 ≠ 클러스터 생성자) CloudShell 의 IAM ARN 을 확인 후 본 PC 에서 access entry 를 추가한다:

```bash
aws sts get-caller-identity --query Arn --output text   # CloudShell 에서 ARN 확인
```

```powershell
aws eks create-access-entry --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> --region ap-northeast-1
aws eks associate-access-policy --cluster-name o11y-cluster --principal-arn <CLOUDSHELL_IAM_ARN> `
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster --region ap-northeast-1
```

### 5) [CloudShell] LBC·Loki·Grafana·k8s 배포

`cs-deploy.sh` 가 helm 설치(`$HOME/bin`) → ECR·SG·VPC 값 조회 → 매니페스트 치환까지 하고 멈춘다. 값을 확인한 뒤 `--apply` 로 적용한다.
`PLAYER` 는 선수 등번호 — Grafana admin 계정(`skills<등번호>`)에 쓰인다.

```bash
cd ~/m4
PLAYER=01 bash cs-deploy.sh            # 조회값 출력 후 종료 (적용 안 함)
```

```bash
PLAYER=01 bash cs-deploy.sh --apply    # ns·SC → LBC 3.4.3 → Loki 18.7.1 → Grafana 12.10.0 → kubectl apply
```

세션이 끊겼다 돌아오면 `source ~/m4.env` 로 PATH·PLAYER·값을 복구한다.

### 6) [CloudShell] pod·TG healthy 확인 (채점 4-2 사전 확인)

```bash
kubectl get sc o11y-gp3
kubectl get pods -n o11y
kubectl get pods -n monitoring
```

pod Ready 후 1~2분 내 TG 등록·healthy 전환:

```bash
for tg in o11y-app-tg o11y-grafana-tg; do
  aws elbv2 describe-target-health --region ap-northeast-1 \
    --target-group-arn "$(aws elbv2 describe-target-groups --names $tg --region ap-northeast-1 --query 'TargetGroups[0].TargetGroupArn' --output text)" \
    --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
done
# 기대: healthy healthy / healthy
```

### 7) [CloudShell] 종단 스모크 (채점 4-4·4-5·4-6)

```bash
APP_ALB=$(aws elbv2 describe-load-balancers --names o11y-app-alb --region ap-northeast-1 --query 'LoadBalancers[0].DNSName' --output text)
curl -s "http://$APP_ALB/healthz"; echo                      # {"status":"ok"}
curl -s "http://$APP_ALB/log?level=error&count=3"; echo      # {"generated":3,"level":"error"}
# 대시보드 3색 범례(error 빨강·warn 노랑·info 초록) 확인용 — 레벨별 건수를 다르게
curl -s "http://$APP_ALB/log?level=warn&count=10"; echo
curl -s "http://$APP_ALB/log?level=info&count=30"; echo
```

Loki 적재 확인 — port-forward 를 백그라운드로 띄우고 한 블록에서 끝낸다:

```bash
kubectl port-forward -n monitoring svc/o11y-loki 3100:3100 >/dev/null 2>&1 &
PF=$!; sleep 3
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' --data-urlencode 'limit=5'; echo
kill $PF
```

Grafana 는 본 PC 브라우저에서(ALB 는 퍼블릭): `http://<grafana_alb_dns>` 접속 → `skills<등번호>` 로그인 → Log Overview 3패널(범례 plain text) + Connections → Data Sources → Loki → Save & Test.

```bash
aws elbv2 describe-load-balancers --names o11y-grafana-alb --region ap-northeast-1 --query 'LoadBalancers[0].DNSName' --output text
```

> 대시보드 기본 구간이 `now-1h` 이고 앱은 요청 없이는 JSON 로그를 만들지 않는다. 접속 직전에 위 `/log` 호출을 해둬야 세 패널에 데이터가 찬다.

### 8) [CloudShell] 셀프 채점

```bash
cd ~/m4
bash mark4-2026-08-04.sh   # 2026-08-04 정정본 (4-5-A 명령의 NBSP 제거). 원본은 mark4.sh
```

## Teardown

### [CloudShell]

```bash
cd ~/m4 && source ~/m4.env   # helm 은 $HOME/bin — 새 세션이면 PATH 복구 필요
kubectl delete -f k8s/rendered/40-tgb-grafana.yaml
kubectl delete -f k8s/rendered/30-tgb-app.yaml      # LBC 가 TG 타깃·SG 규칙 정리
helm uninstall o11y-grafana -n monitoring
helm uninstall o11y-loki -n monitoring
kubectl delete pvc -n monitoring --all              # StatefulSet PVC 는 uninstall 후 잔존 — EBS 고아 볼륨 방지
helm uninstall aws-load-balancer-controller -n kube-system
```

### [본 PC·PowerShell]

```powershell
cd eksctl
eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform
terraform destroy -auto-approve
```
