# Module 1 — Linux 런북 (개인 리눅스 로컬 전용)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계는 자리에 stub 으로 표시했다. 대회 본 PC(Windows 11 + PowerShell 7)에서는 README.md 를 쓴다.

### 1) [본 PC] 배포

```bash
cd terraform
terraform init
terraform apply
terraform output -json > outputs.json
```

### 2) [본 PC] 리소스 검증 + 리허설

```bash
NUM=<등번호>
B=wsc2026-student-score-bucket-$NUM
export AWS_DEFAULT_REGION=ap-southeast-1
SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)

aws s3 ls s3://$B/
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text

# 리허설: test.csv 1회 처리 — 배부물을 provided/module1/ 에 놓아둔 상태여야 한다
aws s3 cp ../../provided/module1/test.csv s3://$B/input/test.csv
sleep 60

aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text
aws dynamodb get-item --table-name wsc2026-student-score \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # 4개만
```

### 3) [본 PC] 채점 직전 상태 — 버킷·테이블을 완전히 비운다

과제 종료 전 반드시 실행한다. 비운 뒤에는 아무것도 올리지 않는다 — test.csv 는 채점자가 올린다.

```bash
# 3-1) 버킷의 모든 객체 삭제 (input/ 포함)
aws s3 rm s3://$B/ --recursive
aws s3 ls s3://$B/ --recursive    # 비어야 한다

# 3-2) DynamoDB 전체 항목 삭제
aws dynamodb scan --table-name wsc2026-student-score \
  --query "Items[].{studentId:studentId,examDate:examDate}" --output json \
  | jq -c '.[]' | while read k; do
    aws dynamodb delete-item --table-name wsc2026-student-score --key "$k"
  done
aws dynamodb scan --table-name wsc2026-student-score --select COUNT --query "Count" --output text   # 0
```

### 4) [CloudShell] 셀프 채점 (선택)

[README.md](README.md) 4단계 수행. **돌렸으면 3) 을 한 번 더 실행해 다시 비워 둔다.**

## Teardown

```bash
cd terraform
terraform destroy
```
