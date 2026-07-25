# Module 1 — NoSQL (ap-southeast-1)

DynamoDB 조건부 예약 + Streams→Lambda 감사 적재 + EC2 Flask 앱. terraform 만으로 배포한다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다 (CloudShell 단계는 공통).

## 디렉토리 구조

```
module-1-nosql/
└── terraform/
    ├── versions.tf variables.tf terraform.tfvars data.tf
    ├── vpc.tf              # VPC + 퍼블릭 서브넷 1개
    ├── dynamodb.tf         # 예약 테이블(GSI/Stream/PITR) + 감사 테이블
    ├── lambda.tf           # 제공 lambda.py 패키징 + Streams 트리거
    ├── iam.tf              # Lambda/EC2 최소 권한
    └── ec2.tf ec2-userdata.sh.tftpl   # 제공 app.py systemd 구동

# 앱/Lambda 소스: ../provided/Module1-NoSQL/ (제공 파일, 수정 금지) — terraform 가 직접 참조
# 채점: ../mark/mark1.sh (CloudShell 에서 실행)
```

## 배포 순서

```powershell
# ===== 본 PC =====
# 0) 이름 대조 — 과제지의 아래 이름이 terraform.tfvars 값과 다르면 tfvars 를 먼저 고친다.
#    bigbae-nosql-reservation-table / gsi-user-reservations / bigbae-nosql-audit-table
#    bigbae-nosql-reservation-audit / EC2 Name 태그 bigbae-nosql-app-ec2
cd terraform
terraform init
terraform apply -auto-approve        # 약 2분. EC2 userdata(pip 설치) 완료까지 +2~3분 대기

$IP = terraform output -raw app_public_ip
curl.exe -s -o NUL -w "%{http_code}" "http://${IP}:8080/healthcheck"   # 200
# 200 이 아니면 userdata 미완료다. 2~3분 뒤 재시도하고, 그래도 안 되면 SSM Session Manager 로
# 접속해 systemctl status bigbae-app 를 확인한다.
```

```bash
# ===== CloudShell (ap-southeast-1) =====
# mark1.sh 는 rm -rf ~/.aws 를 수행한다. 반드시 CloudShell 에서 실행한다.
# Actions → Upload file 로 ../mark/mark1.sh 업로드 후
bash mark1.sh
# 기대 출력: mark.md 1-1 ~ 1-6 기대값과 동일
#   1-5: {"seat_id":"A1","status":"reserved","version":1} 200 / 409 / 409 / 200
#   1-6: 1 / ["reserved", true] / 1 / 0 / 2 / 2
```

## 참고

- 설계 근거: `docs/src/content/docs/setlist/set-07/task-2/deployment.md`
- 채점 항목 ↔ 구현 매핑: 같은 경로의 `mapping.md`
- 함정·미해결 항목: [../NOTES.md](../NOTES.md)
