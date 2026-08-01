# Module 1 — NoSQL (ap-southeast-1)

DynamoDB 예약 테이블(Streams·PITR·sparse GSI) + 감사 테이블, Streams 트리거 Lambda, EC2 Flask 앱. 채점은 CloudShell에서 `mark/mark1.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-1-nosql/
├── terraform/
│   ├── vpc.tf               # 자체 VPC + public 서브넷 + IGW + 라우팅
│   ├── dynamodb.tf          # reservation(GSI·Streams·PITR) + audit 테이블
│   ├── lambda.tf            # 감사 Lambda + Streams ESM + IAM
│   ├── ec2.tf               # SG, IAM, 인스턴스
│   ├── userdata.sh.tftpl    # app.py 배포 + systemd 유닛
│   └── {versions,variables,outputs}.tf
└── README.md

# 앱 소스: task-2/provided/module-1/{app.py,lambda.py,requirements.txt} (제공 원본, 수정 금지) — terraform 이 직접 참조
# 채점: task-2/mark/mark1.sh (CloudShell, ap-southeast-1)
```

## 배포 순서

### 1) [본 PC·PowerShell] 배포

```powershell
cd terraform
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

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy -auto-approve
```
