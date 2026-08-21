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
$n=0; while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$env:CLIENT_IP/health") -ne "200" -and $n -lt 60) { Start-Sleep 10; $n++ }   # 상한 10분

curl.exe -s "http://$env:CLIENT_IP/health"
# → {"status": "ok", "app": "client"}

# Lattice Target Group의 healthy 전환은 배포 완료 후에도 별도로 ~30-60초 더 걸릴 수 있어
# /health 통과 직후 곧바로 호출하면 502/타임아웃이 날 수 있다 — 재시도 루프로 흡수
$n=0; while ((curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://$env:CLIENT_IP/v1/client/orders?id=1001") -ne "200" -and $n -lt 60) { Start-Sleep 10; $n++ }   # 상한 10분

curl.exe -s "http://$env:CLIENT_IP/v1/client/orders?id=1001"
# → {"client": "ok", "service": {"order_id": "1001", "via": "vpc-lattice"}}
#   (service.order_id=1001, service.via=vpc-lattice 확인)

# 채점 2-2: service EC2 는 Public IP 가 없어야 한다
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],PublicIp:PublicIpAddress,State:State.Name}' --output table
# → client 는 PublicIp 존재 / service 는 PublicIp 없음(None)

# 채점 2-4: Target Status=HEALTHY 는 독립 합격 기준이다. 셀프 채점 전에 반드시 HEALTHY 를 확인한다
$TG = aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text
$n=0; while ((aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier $TG --query 'items[0].status' --output text) -ne "HEALTHY" -and $n -lt 60) { Start-Sleep 10; $n++ }   # 상한 10분. $TG 가 None 이면 영원히 안 돈다
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier $TG --query 'items[].{Target:id,Port:port,Status:status}' --output table
# → Status=HEALTHY. UNUSED/UNHEALTHY 상태로 mark2-2.sh 를 돌리면 2-5 는 통과해도 2-4 를 잃는다
```

### [CloudShell] 셀프 채점

```bash
# mark/mark2-2.sh 를 CloudShell 에 업로드(작업 → 파일 업로드) 후 실행. 저장소가 private 이라 git clone 은 쓰지 않는다.
# Windows 에서 파일 업로드 시 CRLF 가 섞일 수 있어 실행 전 가드(멱등 — 이미 LF 여도 무해):
sed -i 's/\r$//' mark2-2.sh
bash mark2-2.sh
```

## 4. Teardown

```powershell
terraform -chdir=terraform destroy -auto-approve
```

1회차가 다음 에러로 실패한다.

```
Error: waiting for VPC Lattice Target Group Attachment (tg-.../i-.../8080) delete:
unexpected state 'UNUSED', wanted target ''. last error: TargetGroupNotInUse
```

**[실측 2026-08-21] 재시도로는 해결되지 않는다** — 같은 지점에서 똑같이 멈춘다. AWS 쪽은 이미 정상
해제된 상태이고(`aws vpc-lattice list-targets ...` 가 빈 목록), 프로바이더 waiter 가 target 이 아니라
**TG 상태**를 보는데 service association 이 먼저 지워져 TG 가 `UNUSED` 로 가면 종료로 인정하지 않는
버그다. 아래처럼 state 에서 떼어낸 뒤 다시 destroy 한다.

```powershell
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier <tg-id> --output table
# → items 가 비어 있으면 AWS 쪽은 이미 해제된 것이다

terraform -chdir=terraform state rm aws_vpclattice_target_group_attachment.service
terraform -chdir=terraform destroy -auto-approve
```

teardown 이 막혔다고 리소스가 남은 게 아니다. **콘솔에서 수동 삭제하지 마라.**
