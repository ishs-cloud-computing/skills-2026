# module-4-msk — MSK 이벤트 스트리밍 (ap-northeast-1)

프라이빗 MSK(IAM 전용 인증, SASL/IAM 9098)로 Go producer가 센서 데이터를 발행하면, Lambda consumer가 이상치를 판별해 정상은 DynamoDB에 저장하고 이상치는 alert 토픽 → SNS 알림 + S3 저장으로 분기한다.

```
module-4-msk/
└── terraform/
    ├── vpc.tf security.tf iam.tf
    ├── msk.tf                        # wsc2026-msk-cluster (3.6.0, t3.small×2, IAM 전용)
    ├── ec2.tf userdata.sh.tpl        # producer: 토픽 생성 + Go 바이너리 systemd 'app'
    ├── dynamodb.tf s3.tf sns.tf
    ├── lambda.tf                     # consumer 2개 (python3.14) + MSK ESM
    ├── bastion.tf                    # kafka CLI 디버깅 겸 채점용
    └── lambda/{sensor_consumer,alert_consumer}/index.py
```

## 배포 (본 PC, PowerShell)

```powershell
cd module-4-msk\terraform

# 1) sensor_consumer 의존성 번들 (없으면 apply 가 precondition 으로 실패한다)
py -m pip install -r lambda\sensor_consumer\requirements.txt -t lambda\sensor_consumer\

# 2) 배포 — MSK 클러스터 생성에 약 30분 소요
terraform init
terraform apply -var "player_number=$env:NUM"
terraform output -json > outputs.json

# 3) 재접속 대비 .env (bash 포맷, 작업규칙 6): 로컬 보관 + bastion 배치.
#    LF 로 써야 bastion 에서 source 된다 (Set-Content 는 CRLF 라 깨짐).
$o = terraform output -json | ConvertFrom-Json
$envtext = (@(
  "export AWS_DEFAULT_REGION=ap-northeast-1"
  "export NUM=$env:NUM"
  "export CLUSTER_ARN=$($o.cluster_arn.value)"
  "export BOOTSTRAP=$($o.bootstrap_brokers_sasl_iam.value)"     # IAM 9098 (producer·bastion kafka CLI)
  "export BOOTSTRAP_TLS=$($o.bootstrap_brokers_tls.value)"      # 비인증 TLS 9094 — tls 모드에서만 값이 찬다
  "export TOPIC_RAW=wsc2026-sensor-raw"
  "export BUCKET=$($o.alert_bucket.value)"
  "export BASTION_IP=$($o.bastion_public_ip.value)"
) -join "`n") + "`n"
[IO.File]::WriteAllText("$PWD\.env", $envtext)
scp .env ec2-user@$($o.bastion_public_ip.value):~/.env         # 비번: Skill53##
```

### 4) 파이프라인 기동 확인 (고정 대기 대신 폴링)

producer EC2 부팅(kafka 다운로드 → IAM jar → 토픽 생성 재시도 최대 5분 → S3 바이너리 수신 → systemd 기동)과 ESM 활성화가 겹쳐 소요가 들쭉날쭉하다. 아래 두 루프가 끝나면 파이프라인이 살아 있는 것이다.

```powershell
# 4-1) ESM 2개가 Enabled 될 때까지 (최대 10분)
$fns = "wsc2026-sensor-consumer","wsc2026-sensor-alert-consumer"
for ($i = 0; $i -lt 40; $i++) {
  $states = $fns | ForEach-Object { aws lambda list-event-source-mappings --function-name $_ --query "EventSourceMappings[0].State" --output text }
  Write-Host "ESM: $($states -join ' / ')"
  if (@($states | Where-Object { $_ -ne "Enabled" }).Count -eq 0) { break }
  Start-Sleep 15
}

# 4-2) 첫 데이터가 DynamoDB 에 들어올 때까지 (최대 10분)
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

토픽 생성 여부는 bastion 의 kafka CLI 로 본다 (아래 "kafka 디버깅").

## producer 인증 모드 (기본 IAM 전용 — 본 PC, PowerShell)

기본 `producer_auth_mode=iam` (`terraform.tfvars`) — 클러스터가 `unauthenticated=false` 로 좁혀지고 `app/producer` 가 SASL/IAM 9098 로 발행한다. 과제지 "MSK 클러스터는 IAM 인증을 통해서만 접근" 요구를 실제로 만족하는 상태이며 **기본 배포에 별도 지정이 필요 없다**.

`app/producer` 는 저장소에 들어 있는 검증된 산출물이다(별도 빌드 불필요). 확인:

```powershell
# cwd: module-4-msk (terraform\ 에서 왔다면 cd ..)
.\check-binary-auth.ps1 app\producer
# 판정: IAM 인증 지원 → SASL/IAM(9098). producer_auth_mode=iam 사용 가능.
```

`tls` 는 **호환성용 예외**다. 제공 바이너리(`provided/module4/app`)는 IAM signer 가 없어 9094 로만 붙으므로, 그 바이너리로 기능만 확인할 때 쓴다. 이 모드는 클러스터에 비인증 리스너를 열어 **과제지 요구를 위반한 상태**가 되므로 채점 대상 배포에는 쓰지 않는다.

```powershell
terraform apply -var "player_number=$env:NUM" -var "producer_auth_mode=tls"   # 기능 확인용
```

이미 뜬 클러스터의 모드를 바꾸면 리스너 변경 in-place 업데이트(~15-30분)가 발생한다.

## 채점 전 정리 (S3 바이너리 제거 — 본 PC, PowerShell)

`bin/app` 은 producer EC2 부팅 다운로드용 임시 스테이징이다. EC2 는 `/opt/app/app` 에 이미
캐시했으므로, 채점 전에 alert 버킷에서 지워 "오류 데이터 저장" 버킷을 데이터만 남긴 상태로 둔다.
(별도 스테이징 버킷을 안 만든 것도 채점 무관 리소스를 남기지 않기 위함.)

```powershell
aws s3 rm "s3://wsc2026-sensor-alert-bucket-$env:NUM/bin/app"
```

지운 뒤 `terraform apply` 를 다시 돌리면 `aws_s3_object.app` 이 재업로드되니, **정리는 마지막 apply 이후·채점 직전에** 한다.

## 리소스 검증 (본 PC, PowerShell)

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

정상 데이터만 흐르는 구간이라 `alert/` 가 비어 있을 수 있다. 이상치는 producer 가 임계치를 넘는 값을 낼 때만 생기므로, 위 두 줄이 비면 몇 분 뒤 다시 본다 — 그래도 계속 비면 `wsc2026-sensor-consumer` 로그에서 alert 토픽 발행이 되는지부터 확인한다.

```powershell
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | Select-String "ALERT -"
```

## bastion·CloudShell 작업 (bash — 원격 셸 안에서 실행)

본 PC 셸이 PowerShell이든 bash든 **여기부터는 접속한 리눅스 셸의 bash 그대로**다. 아래 세 가지가 이 경로에 속한다: 채점 스크립트 `mark/mark2-4.sh` 실행, kafka CLI 디버깅, producer EC2 SSM 세션.

bastion 접속 (키페어 없이 패스워드 로그인):

```bash
# BASTION_IP = terraform output -raw bastion_public_ip  (또는 .env 의 $BASTION_IP)
ssh ec2-user@<BASTION_IP>          # 비번: Skill53## (var.ssh_password, tfvars 로 변경 가능)
```

접속이 안 되면 user_data 의 패스워드 설정이 아직 안 끝난 것 — 부팅 후 1~2분 대기.

채점 스크립트 실행 (`mark/mark2-4.sh` 를 올린 뒤):

```bash
sed -i 's/\r$//' mark2-4.sh          # Windows 에서 올렸으면 CRLF 제거
bash mark2-4.sh 2>&1 | tee mark2-4.out
```

kafka 디버깅 (bastion 접속 후, IAM jar·CLI 는 user_data 로 설치됨):

```bash
source ~/.env    # 배포 때 올린 .env — $BOOTSTRAP(IAM 9098), $TOPIC_RAW 사용
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /opt/kafka/client.properties --describe   # 토픽/파티션/RF 확인
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --consumer.config /opt/kafka/client.properties --topic $TOPIC_RAW --from-beginning --max-messages 5
```

producer EC2 대화형 조사 (SSM 세션 — 본 PC 에서 `aws ssm start-session` 으로 들어간 뒤 bash):

```bash
systemctl status app
journalctl -u app -n 50 --no-pager
cat /var/log/cloud-init-output.log
```

## Linux 런북 (개인 리눅스 로컬 전용 — 대회 본 PC 에서는 위 PowerShell 런북 사용)

위 PowerShell 절차의 bash 대응본이다. 대회 환경(Windows 11 + PowerShell 7)에서는 쓰지 않는다.

배포(리눅스 로컬):

```bash
cd module-4-msk/terraform
pip install -r lambda/sensor_consumer/requirements.txt -t lambda/sensor_consumer/
terraform init
terraform apply -var "player_number=$NUM"
terraform output -json > outputs.json

# 재접속 대비 .env 준비 (작업규칙 6): 로컬 + bastion 양쪽
cat > .env <<EOF
export AWS_DEFAULT_REGION=ap-northeast-1
export NUM=$NUM
export CLUSTER_ARN=$(jq -r '.cluster_arn.value' outputs.json)
export BOOTSTRAP=$(jq -r '.bootstrap_brokers_sasl_iam.value' outputs.json)   # IAM 9098 (bastion kafka CLI 용)
export BOOTSTRAP_TLS=$(jq -r '.bootstrap_brokers_tls.value' outputs.json)    # 비인증 TLS 9094
export TOPIC_RAW=wsc2026-sensor-raw
export BUCKET=$(jq -r '.alert_bucket.value' outputs.json)
export BASTION_IP=$(jq -r '.bastion_public_ip.value' outputs.json)
EOF

# 같은 .env 를 bastion 에도 배치 → 재접속 시 바로 source (client.properties 는 user_data 로 이미 있음)
source .env && scp .env ec2-user@$BASTION_IP:~/.env      # 비번: Skill53##

# 파이프라인 기동 확인 — 고정 대기 대신 폴링 (각 최대 10분)
for i in $(seq 1 40); do
  S=$(for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].State" --output text; done)
  echo "ESM: $S"; [ "$(echo "$S" | grep -cv '^Enabled$')" -eq 0 ] && break; sleep 15
done
for i in $(seq 1 40); do
  N=$(aws dynamodb scan --table-name wsc2026-sensor-data --select COUNT --query "Count" --output text)
  echo "items: $N"; [ "$N" -gt 0 ] && break; sleep 15
done
```

인증 모드 확인·전환(리눅스 로컬):

```bash
./check-binary-auth.sh app/producer            # cwd: module-4-msk
terraform apply -var "player_number=$NUM" -var "producer_auth_mode=tls"   # 기능 확인용 예외
aws s3 rm "s3://$BUCKET/bin/app"               # 채점 전 정리 (마지막 apply 이후)
```

검증(리눅스 로컬 — 실제 채점은 bastion/CloudShell 에서 `mark/mark2-4.sh`):

```bash
source .env
# 4-1 DynamoDB + S3
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text && aws s3api head-bucket --bucket $BUCKET 2>&1
# 4-2 Lambda (python3.14)
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
# 4-3 MSK
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
# 4-4 ESM Enabled ×2
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text; done
# 4-5-A / 4-5-B
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table
# 4-5-C/D 이상치 경로 확인 (alert consumer → S3 + SNS publish 로그)
aws s3 ls s3://$BUCKET/alert/ --recursive | head
aws logs tail /aws/lambda/wsc2026-sensor-alert-consumer --since 15m --format short | grep "alert forwarded"
aws logs tail /aws/lambda/wsc2026-sensor-consumer --since 15m --format short | grep "ALERT -"   # 위가 비면 여기부터
```

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | msk-vpc 192.168.0.0/16, pub/priv a·d, 표의 RTB/IGW/NAT 이름 | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. MSK | wsc2026-msk-cluster, 3.6.0, kafka.t3.small, 프라이빗, HA, IAM 인증 | `msk.tf` (mark 4-3) — 기본 IAM 전용(`producer_auth_mode=iam`), tls 는 호환 우회, 함정 참고 |
| task 3. Topic | sensor-raw 3/2, sensor-alert 1/2, PK sensorId | `userdata.sh.tpl` 토픽 생성 + producer/consumer 가 sensorId 키 사용 |
| task 4. EC2 | wsc2026-sensor-producer t3.small 프라이빗, wsc2026-msk-ec2-role 최소권한 | `ec2.tf` + `iam.tf` + `userdata.sh.tpl` (systemd `app`) |
| task 5. Lambda | consumer 2개 python3.14, MSK 트리거, wsc2026-msk-lambda-role 최소권한 | `lambda.tf` + `lambda/*/index.py` + `iam.tf` (mark 4-2/4-4) |
| task 6. DynamoDB | wsc2026-sensor-data (PK sensorId, SK timestamp) | `dynamodb.tf` (mark 4-1/4-5) |
| task 7. S3 | wsc2026-sensor-alert-bucket-<비번호> | `s3.tf` (mark 4-1) |
| lambda.md | 임계치·alert_reason 문자열·로그 형식·S3 경로 | `lambda/sensor_consumer/index.py`, `lambda/alert_consumer/index.py` |
| Application.md | BOOTSTRAP_SERVERS/TOPIC_RAW, 백그라운드+재부팅 생존 | `userdata.sh.tpl` systemd 유닛 |

## 설계 근거 · 함정

- **MSK 클러스터 생성 ~30분.** producer EC2 의 user_data 가 `bootstrap_brokers_sasl_iam` 을 참조해 클러스터 ACTIVE 후에만 부팅된다 — `-target` 으로 EC2 를 먼저 만들지 말 것. 토픽 생성이 첫 부팅에 자동 수행된다(실패 시 bastion 의 kafka CLI 로 수동 생성 가능).
- **제공 producer 바이너리는 SASL/IAM 을 못 한다** — IAM signer·SigV4 문자열이 통째로 없고 포트가 9094 일 때만 TLS 를 켠다(`BINARY-ANALYSIS.md:10,88` / https://github.com/ishs-cloud-computing/skills-2026/issues/49). 9094 TLS 는 전송 구간 암호화일 뿐 **인증이 없는 접속**이고, 9098 IAM 이 TLS 위에 SASL/IAM 신원 인증까지 얹은 경로다. 과제지 요구는 후자다.
  - **기본 `producer_auth_mode=iam`**: 자체 IAM 바이너리(`app/producer` — 저장소에 있는 검증된 산출물, `app/README.md`)로 9098 SASL/IAM 발행 + 클러스터 `unauthenticated=false`. 과제지 "IAM 인증을 통해서만 접근" 을 만족하는 상태다.
  - **`producer_auth_mode=tls` 는 호환 우회**: 제공 바이너리를 살리려고 `unauthenticated=true` + 9094 리스너를 여는 것뿐이라(`msk.tf`, `security.tf`) 그 자체가 요구 위반이다. 제공 바이너리로 기능만 확인할 때만 쓴다.
  - 9098 을 주면 `unexpected EOF: broker appears to be expecting TLS` 로 영원히 실패. mark 4-3 은 `Sasl.Iam.Enabled` 만 확인. 이미 배포된 클러스터에도 in-place 업데이트(~15-30분, 토픽/데이터 보존).
  - 배포된 EC2 즉시 복구: `sudo sed -i 's/:9098/:9094/g' /etc/systemd/system/app.service && sudo systemctl daemon-reload && sudo systemctl restart app`
  - 기존 클러스터에 리스너 추가 apply 는 `bootstrap_brokers_tls` 가 빈 값이라 EC2 생성에서 `inconsistent final plan` 으로 1회 실패할 수 있다 — MSK 변경은 적용됐으므로 **apply 를 한 번 더**.
- **mark 4-5-A 가 `temperature.S`/`status.S` 를 조회 — DynamoDB 에 Number 로 저장하면 0점.** sensor_consumer 는 전 속성을 String 으로 저장한다.
- **`pip install -t` 를 건너뛰면 zip 에 kafka-python 이 빠져 import 실패로 조용히 죽는다** → `lambda.tf` 의 precondition 이 apply 단계에서 잡아준다. kafka-python 3.0.8 / aws-msk-iam-sasl-signer-python 1.0.2 는 pure-python 이라 Windows/리눅스 동일하게 동작 (Docker 불필요).
- **Lambda 런타임은 python3.14 정확 일치** (mark 4-2). aws provider 6.21+ 에서 지원 — versions.tf `~> 6.54` 로 충족.
- **env 이름 구분**: producer 는 `BOOTSTRAP_SERVERS`(복수), consumer 는 `BOOTSTRAP_SERVER`(단수) — provided 문서 원문 그대로.
- **sensor-consumer 만 VPC 내 배치** — alert 토픽에 produce 하려면 9098 접근이 필요해서다. alert-consumer 는 소비 전용(ESM 이 클러스터 서브넷에서 폴링)이라 VPC 밖 — SNS/S3 를 NAT 없이 호출한다. MSK SG 의 **셀프 참조 인바운드**가 ESM 폴러 ENI 통신에 필수.
- **ESM starting_position=LATEST** — 채점 직전 재배포 시 백로그 재처리로 인한 폭주를 피한다. ESM 은 IAM 전용 클러스터에서 함수 실행 역할로 자동 인증한다(추가 설정 없음).
- task.md 6. DynamoDB 의 속성 표(studentId 등)는 module-1 복붙 오류 — 키 스키마(sensorId/timestamp)가 채점 기준. mark.md 4-0 의 `wsc2026-student-score-bucket` 도 오타이며 mark2-4.sh 의 `wsc2026-sensor-alert-bucket-<비번호>` 가 정답.
- 유의사항 10(채점용 Bastion) 대응 + 프라이빗 MSK 디버깅용으로 bastion 을 둔다. MSK 를 참조하지 않아 클러스터보다 먼저 뜬다.
