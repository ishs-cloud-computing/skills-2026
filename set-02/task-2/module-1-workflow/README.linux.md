# Module 1 — Linux 런북 (개인 리눅스 로컬 전용)

[README.md](README.md) 의 본 PC 단계를 bash 로 옮긴 것. 번호는 README.md 와 1:1 대응이며, CloudShell 단계는 자리에 stub 으로 표시했다. 대회 본 PC(Windows 11 + PowerShell 7)에서는 README.md 를 쓴다.

### 1) [본 PC] 배포

```bash
cd terraform
terraform init
terraform apply
terraform output -json > outputs.json
```

### 2) [본 PC] 리소스 검증

```bash
NUM=<비번호>
B=wsc2026-student-score-bucket-$NUM
export AWS_DEFAULT_REGION=ap-southeast-1
SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)

aws s3 ls s3://$B/
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text
```

### 3) [본 PC] 최종 실행 — 채점 직전, 순서 엄수

```bash
# 3-1) 잔여물 제거
aws s3 rm s3://$B/processed/ --recursive
aws s3 rm s3://$B/error/ --recursive

# 3-2) DynamoDB 비우기
aws dynamodb scan --table-name wsc2026-student-score \
  --query "Items[].{studentId:studentId,examDate:examDate}" --output json \
  | jq -c '.[]' | while read k; do
    aws dynamodb delete-item --table-name wsc2026-student-score --key "$k"
  done

# 3-3) test.csv 업로드 (CloudShell 이면 Actions > Upload file 로 먼저 올린다)
aws s3 cp ../../provided/module1/test.csv s3://$B/input/test.csv

# 3-4) 실행 완료 확인
aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text

# 3-5) 결과 확인
aws dynamodb get-item --table-name wsc2026-student-score \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # 4개만
```

### 4) [CloudShell] 셀프 채점

[README.md](README.md) 4단계 수행.

## Teardown

```bash
cd terraform
terraform destroy
```
