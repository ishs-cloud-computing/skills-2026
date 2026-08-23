# Module 3 — MSK 이벤트 스트리밍 (ap-northeast-1)

프라이빗 MSK 로 Go producer 가 센서 데이터를 발행하면, Lambda consumer 가 이상치를 판별해 정상은 DynamoDB 에 저장하고 이상치는 alert 토픽 → SNS 알림 + S3 저장으로 분기. 채점은 CloudShell 에서 `mark/mark2-3.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

**배포 경로가 둘이다** — `producer_auth_mode` 하나만 다르고 배포 순서·검증 단계는 같다. 어느 쪽인지는 그날 지급된 제공 바이너리가 정하므로 아래 0단계를 먼저 돌린다. 두 경로 비교는 [producer 인증 경로](#producer-인증-경로) 절.

## 디렉토리 구조

```
module-3-msk/
├── terraform/
│   ├── vpc.tf security.tf iam.tf
│   ├── msk.tf                        # wsc2026-msk-cluster (3.6.0, t3.small×2, IAM 전용)
│   ├── ec2.tf userdata.sh.tpl        # producer: 토픽 생성 + Go 바이너리 systemd 'app'
│   ├── dynamodb.tf s3.tf sns.tf
│   ├── lambda.tf                     # consumer 2개 (python3.14) + MSK ESM
│   └── lambda/{sensor_consumer,alert_consumer}/index.py
├── app/producer                      # 자체 IAM 인증 producer (검증된 산출물)
├── select-auth-mode.ps1/.sh          # 대회 당일 쓸 producer_auth_mode 판별 (0단계)
├── check-binary-auth.ps1/.sh         # 개별 바이너리 IAM 지원 여부 검사
├── teardown-eni.ps1/.sh              # destroy 멈춤 대응 — Lambda/MSK 잔여 ENI 정리
└── BINARY-ANALYSIS.md                # 제공 바이너리 리버싱 분석 (2026-08-17 배포본 기준)

# 제공 원본: task-2/provided/module4/ (수정 금지)
#   과제 번호는 RC 에서 4 → 3 으로 내려갔지만 배부 zip 의 디렉터리 이름은 module4 다.
#   재번호되면 terraform/terraform.tfvars 에 provided_dir 한 줄만 넣는다.
# 채점: task-2/mark/mark2-3.sh (CloudShell, ap-northeast-1)
```

## 배포 순서

### 0) [본 PC·PowerShell] 리전 + 인증 경로 판별

리전은 이 셸에서 한 번만 잡아두면 3·4·6단계와 teardown 이 전부 이걸 쓴다. 새 터미널을 열거나
재부팅했으면 다시 잡는다 — 안 잡힌 셸에서 3단계를 돌리면 다른 리전을 조회해 ESM 이 `None`,
DynamoDB 가 0 으로 나온다(리소스는 멀쩡한데 안 보이는 것).

`Set-ExecutionPolicy` 도 여기서 같이 잡는다 — 대회 PC 기본 정책(`Restricted`)이면 이 모듈의
`.ps1` 스크립트(`select-auth-mode`·`check-binary-auth`·`teardown-eni`)가 전부
"실행할 수 없습니다" 로 막힌다. `-Scope Process` 라 이 셸에만 적용되고 새 터미널을 열면 다시
잡아야 한다 — 위 리전 설정과 생명주기가 같다.

배부물 바이너리를 `..\provided\module4\app` 에 먼저 놓는다(저장소엔 문서만 있다) — 없으면 `select-auth-mode` 가 "제공 바이너리 없음"(exit 2)으로 멈춘다. iam 판정에 대비해 자체 바이너리 `app\producer` 가 LFS 포인터(133B)가 아니라 실물(약 10MB)인지도 확인한다 — 포인터면 `git lfs pull`.

```powershell
# cwd: module-3-msk
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
$env:AWS_DEFAULT_REGION = "ap-northeast-1"

.\select-auth-mode.ps1     # 제공 바이너리를 검사해 쓸 모드와 apply 명령을 출력
```

출력된 apply 명령을 1단계에서 그대로 쓴다. IAM 불가 판정이면 `-var "producer_auth_mode=tls"` 가 붙는다.

### 1) [본 PC·PowerShell] 의존성 번들 + 배포

`terraform.tfvars` 의 `player_number` 를 본인 등번호로 바꾼 뒤. 번들을 건너뛰면 apply 가 precondition 으로 실패한다.

```powershell
cd terraform
py -m pip install -r lambda\sensor_consumer\requirements.txt -t lambda\sensor_consumer\
terraform init

# 0단계가 iam 판정 → 아래 그대로. tls 판정 → -var "producer_auth_mode=tls" 를 붙인다.
terraform apply                       # 실측 35분 (MSK 하나가 31분 40초)

terraform output -json > outputs.json
```

### 2) [본 PC·PowerShell] `.env` 생성

재접속 대비(작업규칙 6). 로컬 셸이 끊겨도 이 파일을 `source`(bash) 하거나 값을 옮겨 적으면 바로 잇는다. CloudShell 셀프 채점 때는 Actions > Upload file 로 올려 `source ~/.env` 한다. LF 로 써야 bash 에서 `source` 된다 — `Set-Content` 는 CRLF 라 깨진다.

```powershell
$o = terraform output -json | ConvertFrom-Json
$envtext = (@(
  "export AWS_DEFAULT_REGION=ap-northeast-1"
  "export NUM=$($o.player_number.value)"
  "export CLUSTER_ARN=$($o.cluster_arn.value)"
  "export BOOTSTRAP=$($o.bootstrap_brokers_sasl_iam.value)"     # IAM 9098 (producer kafka CLI)
  "export TOPIC_RAW=wsc2026-sensor-raw"
  "export BUCKET=$($o.alert_bucket.value)"
  "export PRODUCER_ID=$($o.producer_instance_id.value)"
) -join "`n") + "`n"
[IO.File]::WriteAllText("$PWD\.env", $envtext)
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

두 번째 루프가 끝까지 0이면 producer 쪽을 본다 — SSM 으로 서비스와 부팅 로그를 확인한다. `send-command` 를 부팅 후 2~3분 안에 치면 SSM agent 미등록으로 `InvalidInstanceId` 가 난다. `get-command-invocation` 은 명령 실행이 끝나기 전에 조회하면 `InvocationDoesNotExist` — 몇 초면 끝나는 명령이라 5초면 충분하다. 둘 다 나면 몇 분 뒤 재시도.

```powershell
Start-Sleep 180    # SSM agent 등록 대기 (send-command 전, 1회만)

$pid_ = terraform output -raw producer_instance_id
$cmd = aws ssm send-command --instance-ids $pid_ --document-name AWS-RunShellScript `
  --parameters 'commands=["systemctl is-active app","journalctl -u app -n 20 --no-pager","tail -30 /var/log/cloud-init-output.log"]' `
  --query "Command.CommandId" --output text

Start-Sleep 5    # 명령 실행 완료 대기
aws ssm get-command-invocation --command-id $cmd --instance-id $pid_ --query "StandardOutputContent" --output text
```

토픽 생성 여부는 5단계에서 producer 의 kafka CLI 로 본다.

### 4) [본 PC·PowerShell] 리소스 검증

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-1"
$NUM = terraform output -raw player_number      # cwd 가 terraform\ 이 아니면 -chdir=terraform 을 붙인다
$CLUSTER_ARN = aws kafka list-clusters --cluster-name-filter wsc2026-msk-cluster --query "ClusterInfoList[0].ClusterArn" --output text

# 3-1 DynamoDB (sensorId/timestamp) + S3
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text
aws s3api head-bucket --bucket "wsc2026-sensor-alert-bucket-$NUM"
# 3-2 Lambda (python3.14)
foreach ($fn in "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer") { aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text }
# 3-3 MSK (ACTIVE / 3.6.0 / kafka.t3.small / IAM True) + 토픽 (alert 2/1, raw 2/3)
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
aws kafka list-topics --output json --cluster-arn $CLUSTER_ARN --query "Topics[].[TopicName,ReplicationFactor,PartitionCount]"
# 3-4 ESM Enabled ×2
foreach ($fn in "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer") { aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text }
# 3-5 데이터 처리 (temperature/status 가 문자열로 조회돼야 함)
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
# 3-6 producer 동작 (timestamp = YYYY-MM-DDTHH:mm:ss+09:00 표기 강제)
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output json
# 3-6-C 이상치 분기 — alert 토픽 → S3 (alert/{sensorId}/{date}/{timestamp}.json)
aws s3 ls "s3://wsc2026-sensor-alert-bucket-$NUM/alert/" --recursive
# 3-6-D 이상치 분기 — SNS publish 로그 ("<sensorId>: alert forwarded (SNS + S3)")
aws logs tail /aws/lambda/wsc2026-sensor-alert-consumer --since 15m --format short | Select-String "alert forwarded"
```

실측(2026-08-16, 가동 20분): DynamoDB 327건 / `alert/` 객체 32개 — producer 가 약 8초 간격으로 발행하고 그중 10% 정도가 이상치다. `alert/` 가 몇 분째 비어 있으면 `wsc2026-sensor-consumer` 로그에서 alert 토픽 발행부터 확인한다.

```powershell
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | Select-String "ALERT -"
```

### 5) kafka 디버깅 [producer EC2·SSM] + 셀프 채점 [CloudShell]

kafka CLI 는 producer EC2 에 이미 있다 — user_data 가 토픽 생성용으로 `/opt/kafka` + IAM jar + `client.properties` 를 설치한다. 프라이빗 MSK 토픽 확인은 SSM 으로 producer 에 들어가서 한다:

```powershell
# [본 PC] SSM 세션 (Session Manager plugin 필요. 없으면 아래 send-command 로 대신한다)
aws ssm start-session --target (terraform output -raw producer_instance_id)
```

```bash
# [producer EC2] 토픽/파티션/RF 확인 — 인스턴스 역할(최소권한)로 IAM 인증
BOOTSTRAP=<outputs.json 의 bootstrap_brokers_sasl_iam>
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /opt/kafka/client.properties --describe

systemctl status app
journalctl -u app -n 50 --no-pager
cat /var/log/cloud-init-output.log
```

plugin 이 없으면 3단계의 `send-command` 블록에 위 명령을 넣어 비대화형으로 뽑는다. `kafka-console-consumer` 는 producer 역할에 `ReadData` 가 없어(최소권한) 여기서 안 된다 — 메시지 소비 확인은 4단계의 DynamoDB 건수와 3-6-D consumer 로그로 한다.

셀프 채점은 **CloudShell** 에서 한다(채점과 동일 경로). Actions > Upload file 로 `mark2-3.sh` 를 올린 뒤:

```bash
sed -i 's/\r$//' mark2-3.sh
bash mark2-3.sh 2>&1 | tee mark2-3.out
```

### 6) [본 PC·PowerShell] 채점 전 정리 — S3 바이너리 제거

`bin/app` 은 producer EC2 부팅 다운로드용 임시 스테이징이다. EC2 는 `/opt/app/app` 에 이미 캐시했으므로, 채점 전에 alert 버킷에서 지워 "오류 데이터 저장" 버킷을 데이터만 남긴 상태로 둔다. (별도 스테이징 버킷을 안 만든 것도 채점 무관 리소스를 남기지 않기 위함.)

```powershell
aws s3 rm "s3://$(terraform output -raw alert_bucket)/bin/app"
```

지운 뒤 `terraform apply` 를 다시 돌리면 `aws_s3_object.app` 이 재업로드되니, **정리는 마지막 apply 이후·채점 직전에** 한다.

## producer 인증 경로

`producer_auth_mode` 값 하나가 (1) S3 에 올릴 바이너리, (2) 클러스터 `unauthenticated` 설정, (3) producer 에 주입할 부트스트랩 엔드포인트를 한꺼번에 결정한다.

| | `iam` — 정통 (기본값) | `tls` — 대회 제출 우회 |
|---|---|---|
| apply | `terraform apply` | `terraform apply -var "producer_auth_mode=tls"` |
| 바이너리 | 자체 구현 `app/producer` (저장소 산출물, 빌드 불필요) | 제공 원본 `provided/module4/app` |
| MSK 접속 | SASL/IAM 9098 | TLS 9094 (비인증) |
| 클러스터 | `unauthenticated=false`, 9094 리스너·SG 규칙 없음 | `unauthenticated=true` + 9094 리스너, producer↔MSK 간에만 9094 인바운드·아웃바운드 |
| 엔드포인트 | `bootstrap_brokers_sasl_iam` (`_tls` 는 빈 값) | `bootstrap_brokers_tls` |
| 과제지 "IAM 인증을 통해서만 접근" | 만족 (2026-08-16 실배포 검증) | producer 실제 경로 기준으론 미만족 |
| 쓰는 때 | 그날 제공 바이너리가 IAM 인증을 지원할 때 | 지원하지 않을 때 |

- **어느 쪽인지는 미리 정해두지 않는다** — 대회는 제공 바이너리 외 배포를 허용하지 않으므로, 그날 지급된 그 바이너리가 IAM 인증을 하느냐가 경로를 결정한다. 판정은 0단계 `select-auth-mode` 출력을 그대로 따른다.
- 2026-08-17 시점의 배포본은 IAM signer 가 없어 `tls` 로 판정된다([BINARY-ANALYSIS.md](BINARY-ANALYSIS.md)). 출제 측이 바이너리를 교체하면 뒤집히므로 대회 당일 다시 돌린다.
- 클러스터의 SASL/IAM(9098) 은 두 경로 모두 켜져 있고(ESM 폴러·producer kafka CLI 가 쓴다) 채점 3-3 은 `Sasl.Iam.Enabled` 만 보므로 양쪽 다 통과한다.
- 이미 뜬 클러스터의 경로를 바꾸는 apply 는 리스너 in-place 변경 ~15-30분. 부트스트랩 값이 한 번 빈 값으로 잡혀 EC2 생성이 `inconsistent final plan` 으로 1회 실패할 수 있다 — MSK 변경은 이미 적용됐으므로 apply 를 한 번 더 돌린다.

개별 바이너리 판별(모드 판별 자체는 0단계):

```powershell
# cwd: module-3-msk (terraform\ 에서 왔다면 cd ..)
.\check-binary-auth.ps1 app\producer             # 자체 바이너리 — IAM 마커 있음
.\check-binary-auth.ps1 ..\provided\module4\app  # 제공 바이너리 — 이 판정이 모드를 정한다
```

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy                     # 실측 23분 5초 (MSK 클러스터 삭제가 대부분)
```

#### destroy 가 private 서브넷·VPC 삭제에서 멈출 때 — Lambda/MSK ENI 정리

`msk-priv-a`·`msk-priv-d` 삭제와 그 뒤 `msk-vpc` 삭제가 `DependencyViolation` 으로 걸린다. VPC 배치 Lambda(`sensor_consumer`)와 MSK ESM 이 만든 **Hyperplane ENI** 가 terraform state 밖에 남아 서브넷을 잡고 있어서다 — 함수·ESM 이 지워져도 ENI 회수가 수 분\~수십 분 늦다. 먼저 5\~10분 기다렸다가 `terraform destroy` 를 한 번 더 돌리고, 그래도 걸리면 `teardown-eni.ps1` 로 잔여 ENI 를 직접 지운다. VPC ID 는 `terraform output vpc_id` 에서 자동으로 읽는다 — 손으로 옮겨 적지 않는다.

```powershell
# cwd: module-3-msk (terraform\ 에서 왔다면 cd ..)
.\teardown-eni.ps1
```

Lambda Kafka 트리거 삭제 → 이 VPC 를 쓰는 Lambda 의 VPC 연결 해제 → 남은 ENI detach·delete 순으로 진행하고, 각 단계에서 지울 게 없으면(destroy 가 이미 지웠으면) 건너뛴다는 로그를 남긴다. 끝나면:

```powershell
terraform destroy                     # ENI 정리 후 재실행
```

- Lambda Hyperplane ENI 는 detach 직후 바로 delete 가 안 될 수 있다 — `InvalidParameterValue: Network interface is currently in use` 가 나오면 1~2분 뒤 재시도한다.
- ENI 를 다 지웠는데도 VPC 가 안 지워지면 서브넷 외 의존물을 본다: `aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPCID"`(있으면 먼저 삭제), NAT GW 가 `deleting` 인 동안에도 서브넷이 안 지워지므로 `available` 이 아닌 상태가 사라질 때까지 기다린다.

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | msk-vpc 192.168.0.0/16, pub/priv a·d, 표의 RTB/IGW/NAT 이름 | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. MSK | wsc2026-msk-cluster, 3.6.0, kafka.t3.small, 프라이빗, HA, IAM 인증 | `msk.tf` (mark 3-3: `Sasl.Iam.Enabled=True`, 두 경로 공통) — "producer 인증 경로" 절 |
| task 3. Topic | sensor-raw 3/2, sensor-alert 1/2, PK sensorId | `userdata.sh.tpl` 토픽 생성 + producer/consumer 가 sensorId 키 사용 (mark 3-3 이 `aws kafka list-topics` 로 확인) |
| task 4. EC2 | wsc2026-sensor-producer t3.small 프라이빗, wsc2026-msk-ec2-role 최소권한 | `ec2.tf` + `iam.tf` + `userdata.sh.tpl` (systemd `app`) |
| task 5. Lambda | consumer 2개 python3.14, MSK 트리거, wsc2026-msk-lambda-role 최소권한 | `lambda.tf` + `lambda/*/index.py` + `iam.tf` (mark 3-2/3-4) |
| task 6. DynamoDB | wsc2026-sensor-data (PK sensorId, SK timestamp), timestamp ISO 8601 KST, 속성 타입표 | `dynamodb.tf` (mark 3-1) + `lambda/sensor_consumer/index.py` put_item (mark 3-5/3-6) |
| task 7. S3 | wsc2026-sensor-alert-bucket-<등번호>, AccessPointAlias 미설정 | `s3.tf` (mark 3-1 head-bucket 이 `AccessPointAlias: false` 를 본다 — 일반 버킷이면 자동 충족) |
| lambda.md | 임계치·alert_reason 문자열·로그 형식·S3 경로 | `lambda/sensor_consumer/index.py`, `lambda/alert_consumer/index.py` |
| Application.md | BOOTSTRAP_SERVERS/TOPIC_RAW, 백그라운드+재부팅 생존 | `userdata.sh.tpl` systemd 유닛 |

## 설계 근거 · 함정

- **MSK 클러스터 생성 31분 40초(실측).** apply 전체 35분(2026-08-16, bastion 포함 50 리소스 당시) 중 이것 하나가 90% 다 — 나머지는 NAT GW 1분 55초, VPC 배치 sensor_consumer 2분 7초, ESM 55초/2분 37초가 전부다. producer EC2 의 user_data 가 `bootstrap_brokers_sasl_iam` 을 참조해 클러스터 ACTIVE 후에만 부팅된다 — `-target` 으로 EC2 를 먼저 만들지 말 것. 토픽 생성이 첫 부팅에 자동 수행된다(실패 시 producer 의 kafka CLI 로 수동 생성 가능 — 5단계 경로).
- **2026-08-17 배포본의 제공 producer 바이너리는 SASL/IAM 을 못 한다** — IAM signer·SigV4 문자열이 통째로 없고 포트가 9094 일 때만 TLS 를 켠다(`BINARY-ANALYSIS.md` / https://github.com/ishs-cloud-computing/skills-2026/issues/49). 9094 TLS 는 전송 구간 암호화일 뿐 **인증이 없는 접속**이고, 9098 IAM 이 TLS 위에 SASL/IAM 신원 인증까지 얹은 경로 — 과제지 요구는 후자다. 그래서 기본값은 `iam` 이고, 그날 바이너리가 IAM 을 못 하는 것으로 판정되면 `tls` 우회로 내려간다("producer 인증 경로" 절). 바이너리가 교체될 수 있으니 판정은 대회 당일 0단계로 다시 한다.
- **속성 타입은 과제지 6. DynamoDB 표를 그대로 따른다 — `humidity` 만 Number, 나머지는 String.** 특히 `temperature` 는 채점 3-5 가 `temperature.S` 로 조회하므로 Number 로 바꾸면 그 자리가 빈 채 출력돼 0점이다. `sensor_consumer/index.py` 의 put_item 이 유일한 근거지다.
- **`pip install -t` 를 건너뛰면 zip 에 kafka-python 이 빠져 import 실패로 조용히 죽는다** → `lambda.tf` 의 precondition 이 apply 단계에서 잡아준다. kafka-python 3.0.8 / aws-msk-iam-sasl-signer-python 1.0.2 는 pure-python 이라 Windows/리눅스 동일하게 동작 (Docker 불필요).
- **Lambda 런타임은 python3.14 정확 일치** (mark 3-2). aws provider 6.21+ 에서 지원 — versions.tf `~> 6.54` 로 충족.
- **env 이름 구분**: producer 는 `BOOTSTRAP_SERVERS`(복수), consumer 는 `BOOTSTRAP_SERVER`(단수) — provided 문서 원문 그대로.
- **sensor-consumer 만 VPC 내 배치** — alert 토픽에 produce 하려면 9098 접근이 필요해서다. alert-consumer 는 소비 전용(ESM 이 클러스터 서브넷에서 폴링)이라 VPC 밖 — SNS/S3 를 NAT 없이 호출한다. MSK SG 의 **셀프 참조 인바운드**가 ESM 폴러 ENI 통신에 필수.
- **ESM starting_position=LATEST** — 채점 직전 재배포 시 백로그 재처리로 인한 폭주를 피한다. ESM 은 IAM 전용 클러스터에서 함수 실행 역할로 자동 인증한다(추가 설정 없음).
- **mark.md 3-0 의 `BUCKET_NAME="wsc2026-student-score-bucket-…"` 은 원문 오류다** — 3-1 기대 출력은 `wsc2026-sensor-alert-bucket-<등번호>` 이고 `mark2-3.sh` 도 후자를 쓴다. RC 판에서도 안 고쳐졌다(NOTES 정정 로그). 구판에 있던 속성 표 복붙 오류(studentId 등)는 RC 에서 정정됐다.
- **bastion 을 두지 않는다** — mark2-3.sh 는 CloudShell 실행 전제라 채점에 bastion 이 필요 없고, 프라이빗 MSK 디버깅은 producer EC2 의 kafka CLI(SSM 경유)가 대신한다. module-1·2 와 같은 판정으로 task-2 전체를 통일했다(NOTES 결정 로그 2026-08-23). 유의사항 10 문언과의 긴장은 그 로그 참고 — 필요해지면 git 이력의 `bastion.tf` 로 되살린다.
