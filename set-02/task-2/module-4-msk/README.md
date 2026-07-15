# module-4-msk — MSK 이벤트 스트리밍 (ap-northeast-1)

프라이빗 MSK(IAM 인증 + producer용 비인증 TLS 9094)로 Go producer가 센서 데이터를 발행하면, Lambda consumer가 이상치를 판별해 정상은 DynamoDB에 저장하고 이상치는 alert 토픽 → SNS 알림 + S3 저장으로 분기한다.

```
module-4-msk/
└── terraform/
    ├── vpc.tf security.tf iam.tf
    ├── msk.tf                        # wsc2026-msk-cluster (3.6.0, t3.small×2, IAM+비인증TLS)
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
  "export BOOTSTRAP=$($o.bootstrap_brokers_sasl_iam.value)"     # IAM 9098 (bastion kafka CLI)
  "export BOOTSTRAP_TLS=$($o.bootstrap_brokers_tls.value)"      # 비인증 TLS 9094
  "export TOPIC_RAW=wsc2026-sensor-raw"
  "export BUCKET=$($o.alert_bucket.value)"
  "export BASTION_IP=$($o.bastion_public_ip.value)"
) -join "`n") + "`n"
[IO.File]::WriteAllText("$PWD\.env", $envtext)
scp .env ec2-user@$($o.bastion_public_ip.value):~/.env         # 비번: Skill53##
```

apply 완료 후 producer EC2 부팅(토픽 생성 + app 기동)과 ESM 폴러 안정화까지 **3~5분 대기** 후 DynamoDB에 데이터가 쌓이는지 확인한다.

## producer 인증 모드 (기본 TLS / IAM 전환)

기본 `producer_auth_mode=tls` — 제공 바이너리 + 비인증 TLS(9094), 채점 검증 완료 경로. 별도 지정 불필요.

자체 IAM 바이너리로 SASL/IAM(9098) **전용** 접근을 쓰려면:

1. 바이너리가 IAM 을 지원하는지 판별 (제공 바이너리는 TLS 전용이라 iam 모드 불가):
   ```powershell
   .\check-binary-auth.ps1 ..\provided\module4\app     # bash: ./check-binary-auth.sh <경로>
   ```
2. IAM 지원 바이너리를 `app/producer` 에 두고 (LFS 추적, `app/README.md`), apply 시 변수 지정:
   ```powershell
   terraform apply -var "player_number=$env:NUM" -var "producer_auth_mode=iam"
   ```
   ```bash
   terraform apply -var "player_number=$NUM" -var "producer_auth_mode=iam"
   ```

iam 모드는 클러스터를 `unauthenticated=false`(IAM 전용)로 좁혀 과제지 "IAM 인증을 통해서만 접근" 을 실제로 만족한다. 자체 바이너리는 IAM 전용으로 설계됐고, 접속 방식 전환은 `producer_auth_mode` 변수(제공 바이너리 TLS ↔ 자체 IAM 바이너리)로만 이뤄진다. 이미 tls 로 뜬 클러스터를 iam 으로 바꾸면 리스너 변경 in-place 업데이트(~15-30분)가 발생한다.

## 채점 전 정리 (S3 바이너리 제거)

`bin/app` 은 producer EC2 부팅 다운로드용 임시 스테이징이다. EC2 는 `/opt/app/app` 에 이미
캐시했으므로, 채점 전에 alert 버킷에서 지워 "오류 데이터 저장" 버킷을 데이터만 남긴 상태로 둔다.
(별도 스테이징 버킷을 안 만든 것도 채점 무관 리소스를 남기지 않기 위함.)

```powershell
aws s3 rm "s3://wsc2026-sensor-alert-bucket-$env:NUM/bin/app"     # bash: aws s3 rm "s3://$BUCKET/bin/app"
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
```

## Linux 런북 (개인 리눅스 환경용 — 대회에서는 PowerShell 런북 사용)

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
```

검증 (실제 채점은 `mark/mark2-4.sh` 실행):

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
# 이상치 경로 확인 (alert consumer → S3)
aws s3 ls s3://$BUCKET/alert/ --recursive | head
```

bastion 접속 (PowerShell·Linux 공통, 키페어 없이 패스워드 로그인):

```bash
# BASTION_IP = terraform output -raw bastion_public_ip  (또는 .env 의 $BASTION_IP)
ssh ec2-user@<BASTION_IP>          # 비번: Skill53## (var.ssh_password, tfvars 로 변경 가능)
```

접속이 안 되면 user_data 의 패스워드 설정이 아직 안 끝난 것 — 부팅 후 1~2분 대기.

kafka 디버깅 (bastion 접속 후, IAM jar·CLI 는 user_data 로 설치됨):

```bash
source ~/.env    # 배포 때 올린 .env — $BOOTSTRAP(IAM 9098), $TOPIC_RAW 사용
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /opt/kafka/client.properties --describe   # 토픽/파티션/RF 확인
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --consumer.config /opt/kafka/client.properties --topic $TOPIC_RAW --from-beginning --max-messages 5
```

트러블슈팅 진입점: producer EC2 는 SSM 접속(`aws ssm start-session --target <producer_instance_id>`) 후 `systemctl status app`, `cat /var/log/cloud-init-output.log`.

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | msk-vpc 192.168.0.0/16, pub/priv a·d, 표의 RTB/IGW/NAT 이름 | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. MSK | wsc2026-msk-cluster, 3.6.0, kafka.t3.small, 프라이빗, HA, IAM 인증 | `msk.tf` (mark 4-3) — `producer_auth_mode` 로 비인증 TLS 병행(tls)/IAM 전용(iam) 전환, 함정 참고 |
| task 3. Topic | sensor-raw 3/2, sensor-alert 1/2, PK sensorId | `userdata.sh.tpl` 토픽 생성 + producer/consumer 가 sensorId 키 사용 |
| task 4. EC2 | wsc2026-sensor-producer t3.small 프라이빗, wsc2026-msk-ec2-role 최소권한 | `ec2.tf` + `iam.tf` + `userdata.sh.tpl` (systemd `app`) |
| task 5. Lambda | consumer 2개 python3.14, MSK 트리거, wsc2026-msk-lambda-role 최소권한 | `lambda.tf` + `lambda/*/index.py` + `iam.tf` (mark 4-2/4-4) |
| task 6. DynamoDB | wsc2026-sensor-data (PK sensorId, SK timestamp) | `dynamodb.tf` (mark 4-1/4-5) |
| task 7. S3 | wsc2026-sensor-alert-bucket-<비번호> | `s3.tf` (mark 4-1) |
| lambda.md | 임계치·alert_reason 문자열·로그 형식·S3 경로 | `lambda/sensor_consumer/index.py`, `lambda/alert_consumer/index.py` |
| Application.md | BOOTSTRAP_SERVERS/TOPIC_RAW, 백그라운드+재부팅 생존 | `userdata.sh.tpl` systemd 유닛 |

## 설계 근거 · 함정

- **MSK 클러스터 생성 ~30분.** producer EC2 의 user_data 가 `bootstrap_brokers_sasl_iam` 을 참조해 클러스터 ACTIVE 후에만 부팅된다 — `-target` 으로 EC2 를 먼저 만들지 말 것. 토픽 생성이 첫 부팅에 자동 수행된다(실패 시 bastion 의 kafka CLI 로 수동 생성 가능).
- **제공 producer 바이너리는 SASL/IAM 을 못 한다** → 기본 `producer_auth_mode=tls`: 클러스터에 `unauthenticated=true` 병행, app 은 `bootstrap_brokers_tls`(9094). 근거·바이너리 분석: `BINARY-ANALYSIS.md` / https://github.com/ishs-cloud-computing/skills-2026/issues/49
  - **`producer_auth_mode=iam`**: 자체 IAM 바이너리(`app/producer`, placeholder — `app/README.md`)로 9098 SASL/IAM 발행 + 클러스터 `unauthenticated=false`(IAM 전용). 과제지 "IAM 인증을 통해서만 접근" 을 실제로 만족하는 경로. 바이너리는 `AUTH_MODE` env(`iam`/`tls`)로 전환.
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
