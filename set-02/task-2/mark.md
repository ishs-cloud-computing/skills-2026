# 2026년도 전국기능경기대회 채점기준 — 제2과제

## 1. 채점상의 유의사항

| 직종명 | 클라우드 컴퓨팅 |
|---|---|

※ 다음 사항을 유의하여 채점하시오.

- 채점하는 서버가 선수의 서버가 맞는지 확인합니다.
- 채점시 명령어 입력은 CloudShell을 이용할 수 있습니다.

※ 채점기준 양식은 반드시 양식에 맞추어 작성해야 합니다. (채점사이트 입력에 필요)

---

## 2. 채점기준표

### 1) 주요항목별 배점

| 과제번호 | 일련번호 | 주요항목 | 배점 | 채점방법(독립/합의) | 채점시기(진행중/종료후) |
|---|---|---|---|---|---|
| 제2과제 | 1 | Workflow | 7.5 | 독립 ○ | 종료후 ○ |
| 제2과제 | 2 | Real-time Data Analytics | 7.5 | 독립 ○ | 종료후 ○ |
| 제2과제 | 3 | Cloud Event Handling | 7.5 | 독립 ○ | 종료후 ○ |
| 제2과제 | 4 | MSK | 7.5 | 독립 ○ | 종료후 ○ |
| | | **합계** | **30** | | |

### 2) 채점방법 및 기준

| 과제번호 | 일련번호 | 주요항목 | 일련번호 | 세부항목(채점방법) | 배점 |
|---|---|---|---|---|---|
| 제2과제 | 1-1 | S3 Bucket | 1-1 | S3 Bucket + Folder Structure | 1 |
| 제2과제 | 1-2 | DynamoDB | 2-1 | DynamoDB Table + Key Schema | 1 |
| 제2과제 | 1-3 | Lambda | 3-1 | Lambda Function + Runtime + Env | 1.5 |
| 제2과제 | 1-4 | Step Functions | 4-1 | Step Functions State Machine | 1 |
| 제2과제 | 1-5 | Workflow | 5-1 | Workflow Result (Normal) | 1.5 |
| 제2과제 | 1-5 | Workflow | 5-2 | Workflow Result (Error) | 1.5 |
| 제2과제 | 2-1 | EC2 | 1-1 | EC2 Instance | 1 |
| 제2과제 | 2-2 | ALB | 2-1 | ALB Resources | 1 |
| 제2과제 | 2-3 | Kinesis | 3-1 | Kinesis Stream | 1 |
| 제2과제 | 2-3 | Kinesis | 3-2 | Kinesis Data | 1 |
| 제2과제 | 2-4 | Flink | 4-1 | Flink Application | 1 |
| 제2과제 | 2-5 | Application | 5-1 | Application Health | 1 |
| 제2과제 | 2-6 | Systemd Service | 6-1 | Systemd Service | 1.5 |
| 제2과제 | 3-1 | CloudTrail | 1-1 | CloudTrail | 0.5 |
| 제2과제 | 3-2 | SNS | 2-1 | SNS Topic | 0.5 |
| 제2과제 | 3-3 | Lambda | 3-1 | Lambda Functions | 1.5 |
| 제2과제 | 3-4 | EventBridge | 4-1 | EventBridge Rules | 2 |
| 제2과제 | 3-4 | EventBridge | 4-2 | SG Remediation Test | 1.5 |
| 제2과제 | 3-4 | EventBridge | 4-3 | EC2 Type Remediation Test | 1.5 |
| 제2과제 | 4-1 | Resources | 1-1 | Resources | 1 |
| 제2과제 | 4-2 | Lambda | 2-1 | Lambda Functions | 1 |
| 제2과제 | 4-3 | MSK | 3-1 | MSK Cluster Configuration | 2 |
| 제2과제 | 4-3 | MSK | 3-2 | MSK Trigger Mapping | 1.5 |
| 제2과제 | 4-4 | DynamoDB | 4-1 | Data Processing Result | 1 |
| 제2과제 | 4-4 | DynamoDB | 4-2 | Producer Running | 1 |

---

## 3. 세부 채점 항목

### 1) Workflow (ap-southeast-1)

#### 1-0. 채점 준비

1) 웹브라우저로 선수의 AWS 계정에 로그인 후 **ap-southeast-1** Region으로 접속합니다.
2) CloudShell에 접속해 아래 명령어를 입력하고 사용자의 AWS ID와 일치하는지 확인합니다.

```bash
aws sts get-caller-identity --query Account --output text
```

3) 아래 명령어를 실행해 채점환경을 준비합니다. (스크립트 사용 시 스킵)

```bash
BUCKET_NAME="wsc2026-student-score-bucket-(선수 비번호)"
```

#### 1-1. S3 Bucket

1) 아래 명령어를 실행합니다.

```bash
aws s3api head-bucket --bucket $BUCKET_NAME 2>&1 > /dev/null && aws s3 ls s3://$BUCKET_NAME/
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
PRE error/
PRE input/
PRE processed/
```

#### 1-2. DynamoDB

1) 아래 명령어를 입력합니다.

```bash
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
```

2) 출력값이 아래와 일치하는지 확인합니다.

```json
[
  "wsc2026-student-score",
  [
    {
      "AttributeName": "studentId",
      "KeyType": "HASH"
    },
    {
      "AttributeName": "examDate",
      "KeyType": "RANGE"
    }
  ]
]
```

#### 1-3. Lambda

1) 아래 명령어를 입력합니다.

```bash
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
```

2) 출력값이 아래와 일치하는지 확인합니다.

```json
[
  "wsc2026-student-score-function",
  "python3.12",
  {
    "S3_BUCKET": "wsc2026-student-score-bucket-103",
    "DDB_TABLE": "wsc2026-student-score"
  }
]
```

#### 1-4. Step Functions

1) 아래 명령어를 입력합니다.

```bash
SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-student-score-workflow	STANDARD
```

#### 1-5-A. Workflow Result (Normal)

1) 아래 명령어를 입력합니다.

```bash
aws dynamodb get-item --table-name wsc2026-student-score --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text; aws s3 ls s3://$BUCKET_NAME/processed/
```

2) 출력값이 아래와 일치하는지 확인합니다. (강조된 부분만 확인. 아래 값 이외의 값이 출력될 경우 오답.)

```
STU1020	96.6	A
2026-05-31 22:58:16	497 test.csv
```

#### 1-5-B. Workflow Result (Error)

1) 아래 명령어를 입력합니다.

```bash
aws s3 ls s3://$BUCKET_NAME/error/
```

2) 출력값이 아래와 일치하는지 확인합니다. (강조된 부분만 확인. 아래 4개의 값 이외의 값이 출력될 경우 오답.)

```
2026-05-31 13:58:16	267 error_(timestamp)_STU2001.json
2026-05-31 13:58:15	274 error_(timestamp)_STU2002.json
2026-05-31 13:58:15	260 error_(timestamp)_STU2004.json
2026-05-31 13:58:16	262 error_(timestamp)_unknown.json
```

---

### 2) Real-time Data Analytics (ap-northeast-2)

#### 2-0. 채점 준비

1) 웹브라우저로 선수의 AWS 계정에 로그인 후 **ap-northeast-2** Region으로 접속합니다.
2) CloudShell에 접속해 아래 명령어를 입력하고 사용자의 AWS ID와 일치하는지 확인합니다.

```bash
aws sts get-caller-identity --query Account --output text
```

3) 아래 명령어를 실행해 채점환경을 준비합니다. (스크립트 사용 시 스킵)

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].DNSName" --output text); EC2_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-analytics-ec2" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
```

#### 2-1. EC2 Instance

1) 아래 명령어를 입력합니다.

```bash
aws ec2 describe-instances --instance-ids $EC2_ID --query "Reservations[0].Instances[0].{Type:InstanceType,Subnet:SubnetId}" --output text | xargs -I{} aws ec2 describe-subnets --subnet-ids {} --query "Subnets[0].Tags[?Key=='Name'].Value|[0]" --output text 2>/dev/null || aws ec2 describe-subnets --subnet-ids $(aws ec2 describe-instances --instance-ids $EC2_ID --query "Reservations[0].Instances[0].SubnetId" --output text) --query "Subnets[0].Tags[?Key=='Name'].Value|[0]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
analytics-priv-a
```

#### 2-2. ALB Resources

1) 아래 명령어를 입력합니다.

```bash
aws elbv2 describe-listeners --load-balancer-arn $(aws elbv2 describe-load-balancers --names wsc2026-analytics-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Listeners[].[Port,Protocol]" --output text; aws elbv2 describe-target-groups --names wsc2026-analytics-tg --query "TargetGroups[].[TargetGroupName,Port]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
80	HTTP
wsc2026-analytics-tg	5000
```

#### 2-3-A. Kinesis Stream

1) 아래 명령어를 입력합니다.

```bash
aws kinesis describe-stream-summary --stream-name wsc2026-order-stream --query "StreamDescriptionSummary.[StreamName,StreamStatus,StreamModeDetails.StreamMode]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-order-stream	ACTIVE	ON_DEMAND
```

#### 2-3-B. Kinesis Data

1) 아래 명령어를 입력합니다.

```bash
curl -s -X POST http://$ALB_DNS/order | jq .
```

2) 출력값이 아래와 같은 JSON 형식인지 확인합니다. (모든 필드의 값이 채워져있어야 합니다.)

```json
{
  "event_time": "<timestamp>",
  "order_id": "<uuid>",
  "price": "<number>",
  "product_name": "<product_name>",
  "quantity": "<number>"
}
```

#### 2-4. Flink Application

1) 아래 명령어를 입력합니다.

```bash
aws kinesisanalyticsv2 describe-application --application-name wsc2026-analytics-flink --query "ApplicationDetail.[ApplicationName,ApplicationStatus,RuntimeEnvironment]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-analytics-flink	READY	ZEPPELIN-FLINK-3_0
```

#### 2-5. Application Health

1) 아래 명령어를 입력합니다.

```bash
curl -s http://$ALB_DNS/health
```

2) 출력값이 아래와 일치하는지 확인합니다.

```json
{"status":"healthy"}
```

#### 2-6. Systemd Service

1) 아래 명령어를 입력합니다.

```bash
CMD_ID=$(aws ssm send-command --instance-ids $EC2_ID --document-name "AWS-RunShellScript" --parameters '{"commands":["systemctl is-active app && systemctl is-enabled app"]}' --query "Command.CommandId" --output text); sleep 3; aws ssm get-command-invocation --command-id $CMD_ID --instance-id $EC2_ID --query "StandardOutputContent" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
active
enabled
```

---

### 3) Cloud Event Handling (eu-west-1)

#### 3-0. 채점 준비

1) 웹브라우저로 선수의 AWS 계정에 로그인 후 **eu-west-1** Region으로 접속합니다.
2) CloudShell에 접속해 아래 명령어를 입력하고 사용자의 AWS ID와 일치하는지 확인합니다.

```bash
aws sts get-caller-identity --query Account --output text
```

3) 아래 명령어를 실행해 채점환경을 준비합니다. (스크립트 사용 시 스킵)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text); INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-event-ec2" "Name=instance-state-name,Values=running,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text); SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=wsc2026-event-sg" --query "SecurityGroups[0].GroupId" --output text)
```

4) 아래 명령어를 실행해 EC2를 채점 가능한 상태로 수정합니다.

```bash
aws ec2 stop-instances --instance-ids $INSTANCE_ID &>/dev/null; aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 &>/dev/null
```

#### 3-1. Lambda Functions

1) 아래 명령어를 입력합니다.

```bash
aws sns get-topic-attributes --topic-arn arn:aws:sns:eu-west-1:${ACCOUNT_ID}:wsc2026-event-alert --query "Attributes.TopicArn" --output text; for fn in wsc2026-ec2-stop-remediation wsc2026-ec2-terminate-alert wsc2026-sg-remediation wsc2026-tag-alert; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
arn:aws:sns:eu-west-1:(선수 AWS ID):wsc2026-event-alert
wsc2026-ec2-stop-remediation	python3.12
wsc2026-ec2-terminate-alert	python3.12
wsc2026-sg-remediation	python3.12
wsc2026-tag-alert	python3.12
```

#### 3-2. EventBridge Targets

1) 아래 명령어를 입력합니다.

```bash
for rule in wsc2026-ec2-stop-rule wsc2026-ec2-terminate-rule; do echo "$rule -> $(aws events list-targets-by-rule --rule $rule --query "Targets[0].Arn" --output text)"; done
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-ec2-stop-rule -> arn:aws:lambda:eu-west-1:(선수 AWS ID):function:wsc2026-ec2-stop-remediation
wsc2026-ec2-terminate-rule -> arn:aws:lambda:eu-west-1:(선수 AWS ID):function:wsc2026-ec2-terminate-alert
```

#### 3-3. Config Rules

1) 아래 명령어를 입력합니다.

```bash
aws configservice describe-config-rules --config-rule-names wsc2026-sg-ssh-rule wsc2026-required-tags-rule --query "ConfigRules[*].[ConfigRuleName,ConfigRuleState]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-sg-ssh-rule	ACTIVE
wsc2026-required-tags-rule	ACTIVE
```

#### 3-4. Remediation Test

1) 아래 명령어를 입력합니다.

```bash
sleep 30; echo "EC2 State (expect running): $(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].State.Name" --output text)"; echo "SG Inbound Count (expect 0): $(aws ec2 describe-security-groups --group-ids $SG_ID --query "SecurityGroups[0].IpPermissions | length(@)" --output text)"
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
EC2 State (expect running): running
SG Inbound Count (expect 0): 0
```

#### 3-5. Tag Compliance

1) 아래 명령어를 입력합니다.

```bash
aws configservice get-compliance-details-by-config-rule --config-rule-name wsc2026-required-tags-rule --compliance-types NON_COMPLIANT --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId" --output text
```

2) 출력값이 `None`인지 확인합니다.

---

### 4) MSK (ap-northeast-1)

#### 4-0. 채점 준비

1) 웹브라우저로 선수의 AWS 계정에 로그인 후 **ap-northeast-1** Region으로 접속합니다.
2) CloudShell에 접속해 아래 명령어를 입력하고 사용자의 AWS ID와 일치하는지 확인합니다.

```bash
aws sts get-caller-identity --query Account --output text
```

3) 아래 명령어를 실행해 채점환경을 준비합니다. (스크립트 사용 시 스킵)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text); CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter wsc2026-msk-cluster --query "ClusterInfoList[0].ClusterArn" --output text)
BUCKET_NAME="wsc2026-student-score-bucket-(선수 비번호)"
```

#### 4-1. Resources

1) 아래 명령어를 입력합니다.

```bash
aws dynamodb describe-table --table-name wsc2026-sensor-data --query "Table.[TableName,KeySchema[*].AttributeName]" --output text && aws s3api head-bucket --bucket $BUCKET_NAME 2>&1
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-sensor-data
sensorId	timestamp
{
  "BucketArn": "arn:aws:s3:::wsc2026-sensor-alert-bucket-586639730662",
  "BucketRegion": "ap-northeast-1",
  "AccessPointAlias": false
}
```

#### 4-2. Lambda Functions

1) 아래 명령어를 입력합니다.

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda get-function --function-name $fn --query "Configuration.[FunctionName,Runtime]" --output text; done
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-sensor-consumer	python3.14
wsc2026-sensor-alert-consumer	python3.14
```

#### 4-3. MSK Cluster Configuration

1) 아래 명령어를 입력합니다.

```bash
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" --output text
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
wsc2026-msk-cluster	ACTIVE	3.6.0	kafka.t3.small	True
```

#### 4-4. MSK Trigger Mapping

1) 아래 명령어를 입력합니다.

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do aws lambda list-event-source-mappings --function-name $fn --query "EventSourceMappings[0].[State]" --output text; done
```

2) 출력값이 아래와 일치하는지 확인합니다.

```
Enabled
Enabled
```

#### 4-5-A. Data Processing Result

1) 아래 명령어를 입력합니다.

```bash
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 1 --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" --output json
```

2) 출력값이 아래와 같은 형식으로 출력되는지 확인합니다.

```json
{
  "sensorId": "SENSOR-002",
  "temperature": "64.6",
  "status": "NORMAL"
}
```

#### 4-5-B. Producer Running

1) 아래 명령어를 입력합니다.

```bash
aws dynamodb scan --table-name wsc2026-sensor-data --max-items 3 --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table
```

2) 출력값이 아래와 같은 형식(`YYYY-MM-DDTHH:mm:ss±HH:mm`)으로 출력되는지 확인합니다.

```json
{
  "sensorId": "SENSOR-002",
  "timestamp": "2026-06-01T18:28:24+09:00"
}
```
