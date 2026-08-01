# Module 2 — VPC Lattice (ap-northeast-1)

Client/Service VPC 분리 + VPC Lattice Service Network 로 EC2 앱 2대를 연결한다. 채점은 CloudShell 에서 `mark/mark2-2.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-2-lattice/
├── terraform/
│   ├── vpc.tf                    # Client(10.61/16)·Service(10.62/16) VPC + public 서브넷 + IGW + 라우팅
│   ├── sg.tf                     # client/service/sn_assoc 보안 그룹
│   ├── ec2.tf                    # Client·Service EC2 (AL2023, user-data)
│   ├── lattice.tf                # Service Network / Service / Target Group / Listener
│   ├── userdata-client.sh.tftpl
│   ├── userdata-service.sh.tftpl
│   └── {versions,variables,outputs}.tf
├── README.md
└── README.linux.md

# 앱 소스: task-2/provided/module-2/{client_app.py,service_app.py} (제공 원본, 수정 금지) — terraform 이 직접 참조
# 채점: task-2/mark/mark2-2.sh (CloudShell, ap-northeast-1)
```

## 0. IAM 권한 프로브 (대회 시작 직후 1회)

이 모듈은 IAM 리소스를 생성하지 않는다. 프로브는 [module-4 런북 0단계](../module-4-sqs-scaling/README.md)에서 1회만 수행한다.

## 1. 배포

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
```

## 2. 환경변수 (.env)

```powershell
$env:AWS_DEFAULT_REGION  = "ap-northeast-1"
$env:CLIENT_IP           = terraform -chdir=terraform output -raw client_public_ip
$env:SERVICE_DOMAIN      = terraform -chdir=terraform output -raw service_domain
$env:SERVICE_NETWORK_ID  = terraform -chdir=terraform output -raw service_network_id
$env:SERVICE_ID          = terraform -chdir=terraform output -raw service_id
$env:TARGET_GROUP_ID     = terraform -chdir=terraform output -raw target_group_id

@"
`$env:AWS_DEFAULT_REGION  = "ap-northeast-1"
`$env:CLIENT_IP           = "$env:CLIENT_IP"
`$env:SERVICE_DOMAIN      = "$env:SERVICE_DOMAIN"
`$env:SERVICE_NETWORK_ID  = "$env:SERVICE_NETWORK_ID"
`$env:SERVICE_ID          = "$env:SERVICE_ID"
`$env:TARGET_GROUP_ID     = "$env:TARGET_GROUP_ID"
"@ | Set-Content .env.ps1

. .\.env.ps1   # 재접속 시: module-2-lattice 디렉터리에서 `. .\.env.ps1` 만 다시 실행
```

## 3. 검증 (배포 후 ~1-2분 대기: user-data systemd 기동, Client Public IP 경유)

```powershell
while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$env:CLIENT_IP/health") -ne "200") { Start-Sleep 10 }

curl.exe -s "http://$env:CLIENT_IP/health"
# → {"status": "ok", "app": "client"}

curl.exe -s "http://$env:CLIENT_IP/v1/client/orders?id=1001"
# → {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
#   (service.order_id=1001, service.via=vpc-lattice 확인)
```

### [CloudShell] 셀프 채점

```bash
# CloudShell 에서 mark/mark2-2.sh 를 git clone 또는 파일 업로드(Actions → Upload file)로 전송 후 실행.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark/mark2-2.sh
bash mark/mark2-2.sh
```

## 4. Teardown

```powershell
terraform -chdir=terraform destroy -auto-approve
```
