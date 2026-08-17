# Module 4 — MSK 이벤트 스트리밍 (ap-northeast-1)

프라이빗 MSK 로 Go producer 가 센서 데이터를 발행하면, Lambda consumer 가 이상치를 판별해 정상은 DynamoDB 에 저장하고 이상치는 alert 토픽 → SNS 알림 + S3 저장으로 분기. 채점은 bastion 또는 CloudShell 에서 `mark/mark2-4.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(bastion·CloudShell 단계는 공통).

**배포 경로가 둘이다** — `producer_auth_mode` 하나만 다르고 배포 순서·검증 단계는 같다. 어느 쪽인지는 그날 지급된 제공 바이너리가 정하므로 아래 0단계를 먼저 돌린다. 두 경로 비교는 [producer 인증 경로](#producer-인증-경로) 절.

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
└── BINARY-ANALYSIS.md                # 제공 바이너리 리버싱 분석 (2026-08-17 배포본 기준)

# 제공 원본: task-2/provided/module4/ (수정 금지)
# 채점: task-2/mark/mark2-4.sh (bastion 또는 CloudShell, ap-northeast-1)
```

## 배포 순서

### 0) [본 PC·PowerShell] 리전 + 인증 경로 판별

리전은 이 셸에서 한 번만 잡아두면 3·4·6단계와 teardown 이 전부 이걸 쓴다. 새 터미널을 열거나
재부팅했으면 다시 잡는다 — 안 잡힌 셸에서 3단계를 돌리면 다른 리전을 조회해 ESM 이 `None`,
DynamoDB 가 0 으로 나온다(리소스는 멀쩡한데 안 보이는 것).

```powershell
# cwd: module-4-msk
$env:AWS_DEFAULT_REGION = "ap-northeast-1"

.\select-auth-mode.ps1     # 제공 바이너리를 검사해 쓸 모드와 apply 명령을 출력
```

출력된 apply 명령을 1단계에서 그대로 쓴다. IAM 불가 판정이면 `-var "producer_auth_mode=tls"` 가 붙는다.

### 1) [본 PC·PowerShell] 의존성 번들 + 배포

`terraform.tfvars` 의 `player_number` 를 본인 비번호로 바꾼 뒤. 번들을 건너뛰면 apply 가 precondition 으로 실패한다.

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
  "export NUM=$($o.player_number.value)"
  "export CLUSTER_ARN=$($o.cluster_arn.value)"
  "export BOOTSTRAP=$($o.bootstrap_brokers_sasl_iam.value)"     # IAM 9098 (producer·bastion kafka CLI)
  "export TOPIC_RAW=wsc2026-sensor-raw"
  "export BUCKET=$($o.alert_bucket.value)"
  "export BASTION_IP=$($o.bastion_public_ip.value)"
) -join "`n") + "`n"
[IO.File]::WriteAllText("$PWD\.env", $envtext)
```

bastion 으로 올린다. SSM 경로가 기본이다 — 22 를 안 거치므로 아웃바운드 22 가 막힌 망에서도 된다:

```powershell
$bid = terraform output -raw bastion_instance_id
$env_b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\.env"))
aws ssm send-command --instance-ids $bid --document-name AWS-RunShellScript `
  --parameters "commands=[`"echo $env_b64 | base64 -d > /home/ec2-user/.env`",`"chown ec2-user:ec2-user /home/ec2-user/.env`"]" `
  --query "Command.CommandId" --output text
```

22 가 열려 있는 망이면 `scp .env ec2-user@$($o.bastion_public_ip.value):~/.env` (비번 `Skill53##`) 도 된다.
**대회장 망은 22 를 막을 수 있다** — 대회 설계상 채점은 전부 CloudShell/콘솔(443)이라 주최측이 22 를
열어둘 이유가 없다. 위 SSM 경로는 `send-command` 라 로컬에 Session Manager plugin 도 필요 없다.

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

토픽 생성 여부는 5단계의 bastion kafka CLI 로 본다.

### 4) [본 PC·PowerShell] 리소스 검증

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-1"
$NUM = terraform output -raw player_number      # cwd 가 terraform\ 이 아니면 -chdir=terraform 을 붙인다
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

접속 경로 두 가지. **SSM 이 기본**이고, SSH 는 22 가 열린 망에서만 쓴다.

```powershell
# [본 PC] SSM 세션 (22 불필요, 단 Session Manager plugin 은 로컬에 있어야 함)
aws ssm start-session --target (terraform output -raw bastion_instance_id)
sudo su - ec2-user       # 세션은 ssm-user 로 붙으므로 ~/.env 를 쓰려면 전환한다
```

```bash
# [본 PC] SSH — 아웃바운드 22 가 열린 망에서만. 비번: Skill53## (var.ssh_password)
ssh ec2-user@$(terraform output -raw bastion_public_ip)
```

접속이 안 되면 먼저 어느 쪽이 문제인지 가른다: `Test-NetConnection <BASTION_IP> -Port 22` 가 실패하고
`aws ssm describe-instance-information` 의 `PingStatus` 가 `Online` 이면 인스턴스는 정상이고 망이 22 를
막은 것이다(SSM 으로 진행). 둘 다 안 되면 user_data 의 패스워드·agent 설정이 아직인 것 — 부팅 후 1~2분 대기.

```bash
source ~/.env    # 배포 때 올린 .env — $BOOTSTRAP(IAM 9098), $TOPIC_RAW 사용
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP --command-config /opt/kafka/client.properties --describe   # 토픽/파티션/RF 확인
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP --consumer.config /opt/kafka/client.properties --topic $TOPIC_RAW --from-beginning --max-messages 5

sed -i 's/\r$//' mark2-4.sh
bash mark2-4.sh 2>&1 | tee mark2-4.out
```

셀프 채점만 할 거면 bastion 에 붙을 필요 없이 **CloudShell 에서 `mark2-4.sh` 를 돌려도 된다**(README 첫 줄).
22 도 막히고 plugin 도 없는 최악의 경우 이게 유일한 경로다.

producer EC2 를 직접 볼 때는 본 PC 에서 `aws ssm start-session --target <producer_instance_id>` 로 들어간 뒤
(plugin 이 없으면 3단계의 `send-command` 블록을 쓴다):

```bash
systemctl status app
journalctl -u app -n 50 --no-pager
cat /var/log/cloud-init-output.log
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
| 클러스터 | `unauthenticated=false`, 9094 리스너·SG 규칙 없음 | `unauthenticated=true` + 9094 리스너, producer SG 에만 9094 인바운드 |
| 엔드포인트 | `bootstrap_brokers_sasl_iam` (`_tls` 는 빈 값) | `bootstrap_brokers_tls` |
| 과제지 "IAM 인증을 통해서만 접근" | 만족 (2026-08-16 실배포 검증) | producer 실제 경로 기준으론 미만족 |
| 쓰는 때 | 그날 제공 바이너리가 IAM 인증을 지원할 때 | 지원하지 않을 때 |

- **어느 쪽인지는 미리 정해두지 않는다** — 대회는 제공 바이너리 외 배포를 허용하지 않으므로, 그날 지급된 그 바이너리가 IAM 인증을 하느냐가 경로를 결정한다. 판정은 0단계 `select-auth-mode` 출력을 그대로 따른다.
- 2026-08-17 시점의 배포본은 IAM signer 가 없어 `tls` 로 판정된다([BINARY-ANALYSIS.md](BINARY-ANALYSIS.md)). 출제 측이 바이너리를 교체하면 뒤집히므로 대회 당일 다시 돌린다.
- 클러스터의 SASL/IAM(9098) 은 두 경로 모두 켜져 있고(bastion CLI·ESM 이 쓴다) 채점 4-3 은 `Sasl.Iam.Enabled` 만 보므로 양쪽 다 통과한다.
- 이미 뜬 클러스터의 경로를 바꾸는 apply 는 리스너 in-place 변경 ~15-30분. 부트스트랩 값이 한 번 빈 값으로 잡혀 EC2 생성이 `inconsistent final plan` 으로 1회 실패할 수 있다 — MSK 변경은 이미 적용됐으므로 apply 를 한 번 더 돌린다.

개별 바이너리 판별(모드 판별 자체는 0단계):

```powershell
# cwd: module-4-msk (terraform\ 에서 왔다면 cd ..)
.\check-binary-auth.ps1 app\producer             # 자체 바이너리 — IAM 마커 있음
.\check-binary-auth.ps1 ..\provided\module4\app  # 제공 바이너리 — 이 판정이 모드를 정한다
```

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy                     # 50 리소스 / 실측 23분 5초
```

#### destroy 가 private 서브넷·VPC 삭제에서 멈출 때 — Lambda/MSK ENI 정리

`msk-priv-a`·`msk-priv-d` 삭제와 그 뒤 `msk-vpc` 삭제가 `DependencyViolation` 으로 걸린다. VPC 배치 Lambda(`sensor_consumer`)와 MSK ESM 이 만든 **Hyperplane ENI** 가 terraform state 밖에 남아 서브넷을 잡고 있어서다 — 함수·ESM 이 지워져도 ENI 회수가 수 분~수십 분 늦다. 먼저 5~10분 기다렸다가 `terraform destroy` 를 한 번 더 돌리고, 그래도 걸리면 서브넷의 잔여 ENI 를 직접 지운다.

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-1"

# 1) VPC 의 잔여 ENI 조회 — 어느 서브넷을 누가 잡고 있는지 확인
$VPCID = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=msk-vpc" --query "Vpcs[0].VpcId" --output text
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPCID" `
  --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Subnet:SubnetId,Status:Status,Desc:Description,Attach:Attachment.AttachmentId}" --output table
```

`Description` 이 `AWS Lambda VPC ENI-*`(sensor_consumer) 또는 `Amazon MSK network interface`(ESM 폴러) 면 잔여물이다. `Status=in-use` 면 detach 부터, `available` 이면 delete 만 한다.

```powershell
$enis = aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPCID" `
  --query "NetworkInterfaces[].[NetworkInterfaceId,Status,Attachment.AttachmentId]" --output text
foreach ($line in ($enis -split "`n" | Where-Object { $_ })) {
  $eni, $status, $att = $line -split "\s+"
  if ($status -eq "in-use" -and $att -and $att -ne "None") {
    aws ec2 detach-network-interface --attachment-id $att --force
    Start-Sleep 20                    # detach 완료 대기 (available 전이)
  }
  aws ec2 delete-network-interface --network-interface-id $eni
}

terraform destroy                     # ENI 정리 후 재실행
```

- Lambda Hyperplane ENI 는 detach 직후 바로 delete 가 안 될 수 있다 — `InvalidParameterValue: Network interface is currently in use` 가 나오면 1~2분 뒤 재시도한다.
- ENI 를 다 지웠는데도 VPC 가 안 지워지면 서브넷 외 의존물을 본다: `aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPCID"`(있으면 먼저 삭제), NAT GW 가 `deleting` 인 동안에도 서브넷이 안 지워지므로 `available` 이 아닌 상태가 사라질 때까지 기다린다.

## 요구사항 ↔ 구현 매핑

| 항목 | 요구 | 구현 |
|---|---|---|
| task 1. VPC | msk-vpc 192.168.0.0/16, pub/priv a·d, 표의 RTB/IGW/NAT 이름 | `vpc.tf` (`variables.tf` subnets 맵) |
| task 2. MSK | wsc2026-msk-cluster, 3.6.0, kafka.t3.small, 프라이빗, HA, IAM 인증 | `msk.tf` (mark 4-3: `Sasl.Iam.Enabled=True`, 두 경로 공통) — "producer 인증 경로" 절 |
| task 3. Topic | sensor-raw 3/2, sensor-alert 1/2, PK sensorId | `userdata.sh.tpl` 토픽 생성 + producer/consumer 가 sensorId 키 사용 |
| task 4. EC2 | wsc2026-sensor-producer t3.small 프라이빗, wsc2026-msk-ec2-role 최소권한 | `ec2.tf` + `iam.tf` + `userdata.sh.tpl` (systemd `app`) |
| task 5. Lambda | consumer 2개 python3.14, MSK 트리거, wsc2026-msk-lambda-role 최소권한 | `lambda.tf` + `lambda/*/index.py` + `iam.tf` (mark 4-2/4-4) |
| task 6. DynamoDB | wsc2026-sensor-data (PK sensorId, SK timestamp) | `dynamodb.tf` (mark 4-1/4-5) |
| task 7. S3 | wsc2026-sensor-alert-bucket-<비번호> | `s3.tf` (mark 4-1) |
| lambda.md | 임계치·alert_reason 문자열·로그 형식·S3 경로 | `lambda/sensor_consumer/index.py`, `lambda/alert_consumer/index.py` |
| Application.md | BOOTSTRAP_SERVERS/TOPIC_RAW, 백그라운드+재부팅 생존 | `userdata.sh.tpl` systemd 유닛 |

## 설계 근거 · 함정

- **MSK 클러스터 생성 31분 40초(실측).** apply 전체 35분 중 이것 하나가 90% 다 — 나머지 49개 리소스는 NAT GW 1분 55초, VPC 배치 sensor_consumer 2분 7초, ESM 55초/2분 37초가 전부다. producer EC2 의 user_data 가 `bootstrap_brokers_sasl_iam` 을 참조해 클러스터 ACTIVE 후에만 부팅된다 — `-target` 으로 EC2 를 먼저 만들지 말 것. 토픽 생성이 첫 부팅에 자동 수행된다(실패 시 bastion 의 kafka CLI 로 수동 생성 가능).
- **2026-08-17 배포본의 제공 producer 바이너리는 SASL/IAM 을 못 한다** — IAM signer·SigV4 문자열이 통째로 없고 포트가 9094 일 때만 TLS 를 켠다(`BINARY-ANALYSIS.md` / https://github.com/ishs-cloud-computing/skills-2026/issues/49). 9094 TLS 는 전송 구간 암호화일 뿐 **인증이 없는 접속**이고, 9098 IAM 이 TLS 위에 SASL/IAM 신원 인증까지 얹은 경로 — 과제지 요구는 후자다. 그래서 기본값은 `iam` 이고, 그날 바이너리가 IAM 을 못 하는 것으로 판정되면 `tls` 우회로 내려간다("producer 인증 경로" 절). 바이너리가 교체될 수 있으니 판정은 대회 당일 0단계로 다시 한다.
- **mark 4-5-A 가 `temperature.S`/`status.S` 를 조회 — DynamoDB 에 Number 로 저장하면 0점.** sensor_consumer 는 전 속성을 String 으로 저장한다.
- **`pip install -t` 를 건너뛰면 zip 에 kafka-python 이 빠져 import 실패로 조용히 죽는다** → `lambda.tf` 의 precondition 이 apply 단계에서 잡아준다. kafka-python 3.0.8 / aws-msk-iam-sasl-signer-python 1.0.2 는 pure-python 이라 Windows/리눅스 동일하게 동작 (Docker 불필요).
- **Lambda 런타임은 python3.14 정확 일치** (mark 4-2). aws provider 6.21+ 에서 지원 — versions.tf `~> 6.54` 로 충족.
- **env 이름 구분**: producer 는 `BOOTSTRAP_SERVERS`(복수), consumer 는 `BOOTSTRAP_SERVER`(단수) — provided 문서 원문 그대로.
- **sensor-consumer 만 VPC 내 배치** — alert 토픽에 produce 하려면 9098 접근이 필요해서다. alert-consumer 는 소비 전용(ESM 이 클러스터 서브넷에서 폴링)이라 VPC 밖 — SNS/S3 를 NAT 없이 호출한다. MSK SG 의 **셀프 참조 인바운드**가 ESM 폴러 ENI 통신에 필수.
- **ESM starting_position=LATEST** — 채점 직전 재배포 시 백로그 재처리로 인한 폭주를 피한다. ESM 은 IAM 전용 클러스터에서 함수 실행 역할로 자동 인증한다(추가 설정 없음).
- task.md 6. DynamoDB 의 속성 표(studentId 등)는 module-1 복붙 오류 — 키 스키마(sensorId/timestamp)가 채점 기준. mark.md 4-0 의 `wsc2026-student-score-bucket` 도 오타이며 mark2-4.sh 의 `wsc2026-sensor-alert-bucket-<비번호>` 가 정답.
- 유의사항 10(채점용 Bastion) 대응 + 프라이빗 MSK 디버깅용으로 bastion 을 둔다. MSK 를 참조하지 않아 클러스터보다 먼저 뜬다.
