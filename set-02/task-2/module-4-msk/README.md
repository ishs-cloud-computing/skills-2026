# Module 4 — MSK 이벤트 스트리밍 (ap-northeast-1)

프라이빗 MSK 로 Go producer 가 센서 데이터를 발행하면, Lambda consumer 가 이상치를 판별해 정상은 DynamoDB 에 저장하고 이상치는 alert 토픽 → SNS 알림 + S3 저장으로 분기. 채점은 bastion 또는 CloudShell 에서 `mark/mark2-4.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(bastion·CloudShell 단계는 공통).

**배포 경로가 둘이다.** 배포 순서·검증 단계는 공통이고 `producer_auth_mode` 하나만 다르다:

| 경로 | 값 | producer 바이너리 | MSK 접속 | 언제 |
|---|---|---|---|---|
| **정통** (기본) | `iam` | 자체 구현 `app/producer` | SASL/IAM 9098 | 제공 바이너리가 IAM 인증을 지원할 때. 과제지 "IAM 인증을 통해서만 접근" 요구를 실제로 만족 |
| **대회 제출 우회** | `tls` (`-var` 지정) | 제공 원본 `provided/module4/app` | TLS 9094 (비인증) | 제공 바이너리가 IAM 인증을 못 할 때(2026-08-17 배포본이 그렇다). 제공 바이너리 외 배포가 안 되므로 이 경로뿐 |

**어느 쪽인지는 그날 지급된 제공 바이너리가 결정한다 — 대회 당일 아래를 먼저 돌린다:**

```powershell
# cwd: module-4-msk
.\select-auth-mode.ps1     # 제공 바이너리를 검사해 쓸 모드와 apply 명령을 출력
```

상세와 전환 절차는 아래 [producer 인증 경로](#producer-인증-경로-정통--대회-제출-우회) 절.

## 디렉토리 구조

```
module-4-msk/
├── terraform/
│   ├── vpc.tf security.tf iam.tf
│   ├── msk.tf                        # wsc2026-msk-cluster (3.6.0, t3.small×2, IAM 전용)
│   ├── ec2.tf userdata.sh.tpl        # producer: 토픽 생성 + Go 바이너리 systemd 'app'
│   ├── dynamodb.tf s3.tf sns.tf
│   ├── lambda.tf                     # consumer 2개 (python3.14) + MSK ESM
│   ├── bastion.tf                    # kafka CLI 디버깅 겸 채점용
│   └── lambda/{sensor_consumer,alert_consumer}/index.py
├── app/producer                      # 자체 IAM 인증 producer (검증된 산출물)
├── select-auth-mode.ps1/.sh          # 대회 당일 쓸 producer_auth_mode 판별 (0단계)
├── check-binary-auth.ps1/.sh         # 개별 바이너리 IAM 지원 여부 검사
└── BINARY-ANALYSIS.md                # 제공 바이너리 리버싱 분석 (IAM 불가 근거)

# 제공 원본: task-2/provided/module4/ (수정 금지)
# 채점: task-2/mark/mark2-4.sh (bastion 또는 CloudShell, ap-northeast-1)
```

## 배포 순서

### 0) [본 PC·PowerShell] 인증 경로 판별

그날 지급된 제공 바이너리가 IAM 인증을 지원하는지에 따라 1단계 apply 명령이 갈린다. 먼저 판별한다:

```powershell
# cwd: module-4-msk
.\select-auth-mode.ps1
```

출력된 apply 명령을 1단계에서 그대로 쓴다. IAM 불가 판정이면 `-var "producer_auth_mode=tls"` 가 붙는다.

### 1) [본 PC·PowerShell] 의존성 번들 + 배포

`terraform.tfvars` 의 `player_number` 를 본인 비번호로 바꾼 뒤. 번들을 건너뛰면 apply 가 precondition 으로 실패한다. apply 명령은 0단계 판별 결과를 따른다.

```powershell
cd terraform
py -m pip install -r lambda\sensor_consumer\requirements.txt -t lambda\sensor_consumer\
terraform init

# 0단계가 iam 판정 → 아래 그대로. tls 판정 → -var "producer_auth_mode=tls" 를 붙인다.
terraform apply                       # 50 리소스 / 실측 35분 (MSK 하나가 31분 40초)

terraform output -json > outputs.json
```

### 2) [본 PC·PowerShell] `.env` 생성 + bastion 배치

재접속 대비(작업규칙 6). LF 로 써야 bastion 에서 `source` 된다 — `Set-Content` 는 CRLF 라 깨진다.

```powershell
$o = terraform output -json | ConvertFrom-Json
$envtext = (@(
  "export AWS_DEFAULT_REGION=ap-northeast-1"
  "export NUM=$env:NUM"
  "export CLUSTER_ARN=$($o.cluster_arn.value)"
  "export BOOTSTRAP=$($o.bootstrap_brokers_sasl_iam.value)"     # IAM 9098 (producer·bastion kafka CLI)
  "export TOPIC_RAW=wsc2026-sensor-raw"
  "export BUCKET=$($o.alert_bucket.value)"
  "export BASTION_IP=$($o.bastion_public_ip.value)"
) -join "`n") + "`n"
[IO.File]::WriteAllText("$PWD\.env", $envtext)
scp .env ec2-user@$($o.bastion_public_ip.value):~/.env         # 비번: Skill53##
```

### 3) [본 PC·PowerShell] 파이프라인 기동 확인 (고정 대기 대신 폴링)

**실측(2026-08-16)에서는 apply 가 끝난 시점에 이미 돌고 있었다** — producer `app` 은 apply 종료 1분 48초 **전**에 active 였고, 첫 DynamoDB 레코드·첫 S3 alert 객체가 apply 종료 직후에 찍혔다. 두 루프 모두 1회 만에 통과하는 게 정상이고, 여러 바퀴 도는 건 이상 신호다.

```powershell
# 3-1) ESM 2개가 Enabled 될 때까지 (최대 10분)
$fns = "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer"
for ($i = 0; $i -lt 40; $i++) {
  $states = $fns | ForEach-Object { aws lambda list-event-source-mappings --function-name $_ --query "EventSourceMappings[0].State" --output text }
  Write-Host "ESM: $($states -join ' / ')"
  if (@($states | Where-Object { $_ -ne "Enabled" }).Count -eq 0) { break }
  Start-Sleep 15
}

# 3-2) 첫 데이터가 DynamoDB 에 들어올 때까지 (최대 10분)
for ($i = 0; $i -lt 40; $i++) {
  $n = aws dynamodb scan --table-name wsc2026-sensor-data --select COUNT --query "Count" --output text
  Write-Host "items: $n"
  if ([int]$n -gt 0) { break }
  Start-Sleep 15
}
```

두 번째 루프가 끝까지 0이면 producer 쪽을 본다 — SSM 으로 서비스와 부팅 로그를 확인한다.

```powershell
$pid_ = terraform output -raw producer_instance_id
aws ssm send-command --instance-ids $pid_ --document-name AWS-RunShellScript `
  --parameters 'commands=["systemctl is-active app","journalctl -u app -n 20 --no-pager","tail -30 /var/log/cloud-init-output.log"]' `
  --query "Command.CommandId" --output text
# 몇 초 뒤 결과 조회 (<CMD_ID> 는 위 출력)
aws ssm get-command-invocation --command-id <CMD_ID> --instance-id $pid_ --query "StandardOutputContent" --output text
```

토픽 생성 여부는 5단계의 bastion kafka CLI 로 본다.

### 4) [본 PC·PowerShell] 리소스 검증

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-1"
$NUM = $env:NUM
$CLUSTER_ARN = aws kafka list-clusters --cluster-name-filter wsc2026-msk-cluster --query "ClusterInfoList[0].ClusterArn" --output text

# 4-1 DynamoDB (sensorId/timestamp) + S3
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text
aws s3api head-bucket --bucket "wsc2026-sensor-alert-bucket-$NUM"
# 4-2 Lambda (python3.14)
foreach ($fn in "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer") { aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text }
# 4-3 MSK (ACTIVE / 3.6.0 / kafka.t3.small / IAM True)
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
# 4-4 ESM Enabled ×2
foreach ($fn in "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer") { aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text }
# 4-5-A 데이터 처리 (temperature/status 가 문자열로 조회돼야 함)
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
# 4-5-B producer 동작 (timestamp = YYYY-MM-DDTHH:mm:ss+09:00)
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table
# 4-5-C 이상치 분기 — alert 토픽 → S3 (alert/{sensorId}/{date}/{timestamp}.json)
aws s3 ls "s3://wsc2026-sensor-alert-bucket-$NUM/alert/" --recursive
# 4-5-D 이상치 분기 — SNS publish 로그 ("<sensorId>: alert forwarded (SNS + S3)")
aws logs tail /aws/lambda/wsc2026-sensor-alert-consumer --since 15m --format short | Select-String "alert forwarded"
```

실측(2026-08-16, 가동 20분): DynamoDB 327건 / `alert/` 객체 32개 — producer 가 약 8초 간격으로 발행하고 그중 10% 정도가 이상치다. `alert/` 가 몇 분째 비어 있으면 `wsc2026-sensor-consumer` 로그에서 alert 토픽 발행부터 확인한다.

```powershell
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | Select-String "ALERT -"
```

### 5) [bastion·bash] kafka 디버깅 + 셀프 채점

키페어 없이 패스워드 로그인. 접속이 안 되면 user_data 의 패스워드 설정이 아직 안 끝난 것 — 부팅 후 1~2분 대기.

```bash
# BASTION_IP = terraform output -raw bastion_public_ip  (또는 .env 의 $BASTION_IP)
ssh ec2-user@<BASTION_IP>          # 비번: Skill53## (var.ssh_password, tfvars 로 변경 가능)
```

```bash
source ~/.env    # 배포 때 올린 .env — $BOOTSTRAP(IAM 9098), $TOPIC_RAW 사용
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /opt/kafka/client.properties --describe   # 토픽/파티션/RF 확인
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --consumer.config /opt/kafka/client.properties --topic $TOPIC_RAW --from-beginning --max-messages 5

sed -i 's/\r$//' mark2-4.sh
bash mark2-4.sh 2>&1 | tee mark2-4.out
```

producer EC2 를 직접 볼 때는 본 PC 에서 `aws ssm start-session --target <producer_instance_id>` 로 들어간 뒤:

```bash
systemctl status app
journalctl -u app -n 50 --no-pager
cat /var/log/cloud-init-output.log
```

### 6) [본 PC·PowerShell] 채점 전 정리 — S3 바이너리 제거

`bin/app` 은 producer EC2 부팅 다운로드용 임시 스테이징이다. EC2 는 `/opt/app/app` 에 이미 캐시했으므로, 채점 전에 alert 버킷에서 지워 "오류 데이터 저장" 버킷을 데이터만 남긴 상태로 둔다. (별도 스테이징 버킷을 안 만든 것도 채점 무관 리소스를 남기지 않기 위함.)

```powershell
aws s3 rm "s3://wsc2026-sensor-alert-bucket-$env:NUM/bin/app"
```

지운 뒤 `terraform apply` 를 다시 돌리면 `aws_s3_object.app` 이 재업로드되니, **정리는 마지막 apply 이후·채점 직전에** 한다.

## producer 인증 경로 (정통 / 대회 제출 우회)

배포 순서·검증 단계는 두 경로가 동일하다. `producer_auth_mode` 값 하나가 (1) S3 에 올릴 바이너리, (2) 클러스터 `unauthenticated` 설정, (3) producer 에 주입할 부트스트랩 엔드포인트를 한꺼번에 결정한다.

### A. 정통 경로 — `iam` (기본값, 별도 지정 불필요)

과제지 "MSK 클러스터는 IAM 인증을 통해서만 접근" 요구를 실제로 만족하는 구성. 자체 구현한 `app/producer`(저장소에 들어 있는 검증된 산출물, 별도 빌드 불필요)가 SASL/IAM 9098 로 발행한다.

```powershell
terraform apply                      # producer_auth_mode=iam (terraform.tfvars 기본값)
```

- 클러스터가 `unauthenticated=false` 로 좁혀지고 9094 리스너·SG 규칙이 만들어지지 않는다.
- 엔드포인트는 `terraform output bootstrap_brokers_sasl_iam`. `bootstrap_brokers_tls` 는 빈 값이다.
- 2026-08-16 실배포 검증 완료 — `Sasl.Iam.Enabled=True` / `Unauthenticated.Enabled=False` 상태에서 DynamoDB 적재·alert 분기까지 정상 동작.

### B. 대회 제출 우회 경로 — `tls` (`-var` 로 지정)

대회는 제공 바이너리(`provided/module4/app`) 외 배포를 허용하지 않는다. 그 바이너리는 리버싱으로 IAM signer 자체가 없음이 확정됐고(`BINARY-ANALYSIS.md`) 접속 가능한 경로는 9094 TLS(비인증)뿐이다 — **대회 당일 실제로 제출할 수 있는 건 이쪽이다.**

```powershell
terraform apply -var "producer_auth_mode=tls"     # 리스너 in-place 변경 ~15-30분
```

- 클러스터에 `unauthenticated=true` + 9094 리스너가 열리고, producer SG 에만 9094 인바운드가 붙는다.
- 엔드포인트는 `terraform output bootstrap_brokers_tls`.
- 클러스터의 SASL/IAM(9098) 자체는 이 경로에서도 켜져 있다 — bastion CLI·ESM 이 쓰고, 채점 4-3(`Sasl.Iam.Enabled`)도 이걸 보므로 통과한다.
- **한계**: 과제지 문구를 producer 실제 경로 기준으론 리터럴로 만족하지 못한다. 제공 바이너리의 구조적 한계라 대회에선 감수한다.
- 기존 클러스터의 리스너 모드를 바꾸는 apply 는 부트스트랩 값이 한 번 빈 값으로 잡혀 EC2 생성에서 `inconsistent final plan` 으로 1회 실패할 수 있다 — MSK 변경은 이미 적용됐으므로 apply 를 한 번 더 돌린다.

### 판별 스크립트

모드 판별은 0단계 `select-auth-mode.ps1` 이 한다 — 제공 바이너리를 검사해 쓸 모드와 apply 명령을 출력한다. 개별 바이너리를 따로 보고 싶으면:

```powershell
# cwd: module-4-msk (terraform\ 에서 왔다면 cd ..)
.\check-binary-auth.ps1 app\producer             # IAM 인증 지원  → iam 경로 (기본)
.\check-binary-auth.ps1 ..\provided\module4\app  # IAM 마커 0건   → tls 경로만 가능 (2026-08-17 배포본)
```

분석 전체는 [BINARY-ANALYSIS.md](BINARY-ANALYSIS.md).

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy                     # 50 리소스 / 실측 23분 5초
```

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | msk-vpc 192.168.0.0/16, pub/priv a·d, 표의 RTB/IGW/NAT 이름 | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. MSK | wsc2026-msk-cluster, 3.6.0, kafka.t3.small, 프라이빗, HA, IAM 인증 | `msk.tf` (mark 4-3: `Sasl.Iam.Enabled=True` — 두 경로 공통). 기본은 IAM 전용(`iam`), 대회 제출은 `-var producer_auth_mode=tls` 우회, 함정 참고 |
| task 3. Topic | sensor-raw 3/2, sensor-alert 1/2, PK sensorId | `userdata.sh.tpl` 토픽 생성 + producer/consumer 가 sensorId 키 사용 |
| task 4. EC2 | wsc2026-sensor-producer t3.small 프라이빗, wsc2026-msk-ec2-role 최소권한 | `ec2.tf` + `iam.tf` + `userdata.sh.tpl` (systemd `app`) |
| task 5. Lambda | consumer 2개 python3.14, MSK 트리거, wsc2026-msk-lambda-role 최소권한 | `lambda.tf` + `lambda/*/index.py` + `iam.tf` (mark 4-2/4-4) |
| task 6. DynamoDB | wsc2026-sensor-data (PK sensorId, SK timestamp) | `dynamodb.tf` (mark 4-1/4-5) |
| task 7. S3 | wsc2026-sensor-alert-bucket-<비번호> | `s3.tf` (mark 4-1) |
| lambda.md | 임계치·alert_reason 문자열·로그 형식·S3 경로 | `lambda/sensor_consumer/index.py`, `lambda/alert_consumer/index.py` |
| Application.md | BOOTSTRAP_SERVERS/TOPIC_RAW, 백그라운드+재부팅 생존 | `userdata.sh.tpl` systemd 유닛 |

## 설계 근거 · 함정

- **MSK 클러스터 생성 31분 40초(실측).** apply 전체 35분 중 이것 하나가 90% 다 — 나머지 49개 리소스는 NAT GW 1분 55초, VPC 배치 sensor_consumer 2분 7초, ESM 55초/2분 37초가 전부다. producer EC2 의 user_data 가 `bootstrap_brokers_sasl_iam` 을 참조해 클러스터 ACTIVE 후에만 부팅된다 — `-target` 으로 EC2 를 먼저 만들지 말 것. 토픽 생성이 첫 부팅에 자동 수행된다(실패 시 bastion 의 kafka CLI 로 수동 생성 가능).
- **제공 producer 바이너리는 SASL/IAM 을 못 한다** — IAM signer·SigV4 문자열이 통째로 없고 포트가 9094 일 때만 TLS 를 켠다(`BINARY-ANALYSIS.md` / https://github.com/ishs-cloud-computing/skills-2026/issues/49). 9094 TLS 는 전송 구간 암호화일 뿐 **인증이 없는 접속**이고, 9098 IAM 이 TLS 위에 SASL/IAM 신원 인증까지 얹은 경로 — 과제지 요구는 후자다. 그래서 기본값은 IAM 전용(`iam` + 자체 `app/producer`)이다. 다만 대회는 제공 바이너리 외 배포를 허용하지 않으므로 **대회 당일 제출은 `-var producer_auth_mode=tls` 로 9094 TLS 우회 경로를 쓴다** — 두 경로 다 런북 "producer 인증 경로" 절에 있다.
- **mark 4-5-A 가 `temperature.S`/`status.S` 를 조회 — DynamoDB 에 Number 로 저장하면 0점.** sensor_consumer 는 전 속성을 String 으로 저장한다.
- **`pip install -t` 를 건너뛰면 zip 에 kafka-python 이 빠져 import 실패로 조용히 죽는다** → `lambda.tf` 의 precondition 이 apply 단계에서 잡아준다. kafka-python 3.0.8 / aws-msk-iam-sasl-signer-python 1.0.2 는 pure-python 이라 Windows/리눅스 동일하게 동작 (Docker 불필요).
- **Lambda 런타임은 python3.14 정확 일치** (mark 4-2). aws provider 6.21+ 에서 지원 — versions.tf `~> 6.54` 로 충족.
- **env 이름 구분**: producer 는 `BOOTSTRAP_SERVERS`(복수), consumer 는 `BOOTSTRAP_SERVER`(단수) — provided 문서 원문 그대로.
- **sensor-consumer 만 VPC 내 배치** — alert 토픽에 produce 하려면 9098 접근이 필요해서다. alert-consumer 는 소비 전용(ESM 이 클러스터 서브넷에서 폴링)이라 VPC 밖 — SNS/S3 를 NAT 없이 호출한다. MSK SG 의 **셀프 참조 인바운드**가 ESM 폴러 ENI 통신에 필수.
- **ESM starting_position=LATEST** — 채점 직전 재배포 시 백로그 재처리로 인한 폭주를 피한다. ESM 은 IAM 전용 클러스터에서 함수 실행 역할로 자동 인증한다(추가 설정 없음).
- task.md 6. DynamoDB 의 속성 표(studentId 등)는 module-1 복붙 오류 — 키 스키마(sensorId/timestamp)가 채점 기준. mark.md 4-0 의 `wsc2026-student-score-bucket` 도 오타이며 mark2-4.sh 의 `wsc2026-sensor-alert-bucket-<비번호>` 가 정답.
- 유의사항 10(채점용 Bastion) 대응 + 프라이빗 MSK 디버깅용으로 bastion 을 둔다. MSK 를 참조하지 않아 클러스터보다 먼저 뜬다.
