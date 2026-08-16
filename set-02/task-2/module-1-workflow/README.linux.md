# module-1-workflow — Linux 런북 (개인 리눅스 로컬 전용)

대회 본 PC 는 Windows 11 + PowerShell 7 이다. 대회에서는 [README.md](README.md) 의 PowerShell 런북을 쓰고, 이 파일은 개인 리눅스 환경에서 연습·검증할 때만 쓴다. bastion·CloudShell 안에서 실행하는 bash 절차는 이 파일이 아니라 README.md 에 있다.

bastion/CloudShell도 리눅스라 그대로 동작하지만, 이 섹션의 목적은 로컬 리눅스에서의 연습·검증이다.

```bash
NUM=<비번호>
B=wsc2026-student-score-bucket-$NUM
aws configure set region ap-southeast-1
SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)

# 검증 1-1 ~ 1-4
aws s3 ls s3://$B/
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text

# 최종 실행 절차 (동일 순서)
aws s3 rm s3://$B/processed/ --recursive
aws s3 rm s3://$B/error/ --recursive
aws dynamodb scan --table-name wsc2026-student-score \
  --query "Items[].{studentId:studentId,examDate:examDate}" --output json \
  | jq -c '.[]' | while read k; do
    aws dynamodb delete-item --table-name wsc2026-student-score --key "$k"
  done
# CloudShell 이면 Actions > Upload file 로 test.csv 를 올린 뒤:
aws s3 cp test.csv s3://$B/input/test.csv
aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text
aws dynamodb get-item --table-name wsc2026-student-score \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # 4개만
```

---

