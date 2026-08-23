#!/bin/bash

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "ACCOUNT ID: $ACCOUNT_ID"
aws configure set region ap-southeast-1

read -p "등번호: " NUM
BUCKET_NAME="wsc2026-student-score-bucket-${NUM}"

# 1-0 채점 준비 — 채점지: 버킷·테이블 클렌징 확인 → input/test.csv 업로드 → 60초 대기
# 클렌징이 안 되어 있으면 채점자는 1-1·1-5·1-6 을 모두 오답 처리한다.
echo ====================
echo "  1-0 채점 준비 (클렌징 확인)"
echo ====================
echo "[S3] 아래 목록이 비어 있어야 한다:"
aws s3 ls s3://$BUCKET_NAME/ --recursive
echo "[DynamoDB] 아래 Count 가 0 이어야 한다:"
aws dynamodb scan --table-name wsc2026-student-score --select COUNT --query "Count" --output text

read -p "위 두 개가 비어 있으면 Enter (아니면 Ctrl-C 후 정리) " _
if [ -f ./test.csv ]; then
  aws s3 cp ./test.csv s3://$BUCKET_NAME/input/test.csv
else
  echo "!! test.csv 가 현재 디렉터리에 없다 — CloudShell 에 업로드한 뒤 다시 실행한다"
  exit 1
fi
echo "60초 대기 (채점지: 업로드 시점부터 60초 이내 워크플로우 완료)"
sleep 60

# 1-1 S3 Bucket + Folder Structure
echo ====================
echo "  1-1 S3 Bucket + Folder Structure"
echo ====================
aws s3api head-bucket --bucket $BUCKET_NAME 2>&1 > /dev/null && aws s3 ls s3://$BUCKET_NAME/

# 1-2 DynamoDB Table + Key Schema
echo ====================
echo "  1-2 DynamoDB Table + Key Schema"
echo ====================
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json

# 1-3 Lambda Function + Runtime + Env
echo ====================
echo "  1-3 Lambda Function + Runtime + Env"
echo ====================
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json

# 1-4 Step Functions State Machine
echo ====================
echo "  1-4 Step Functions State Machine"
echo ====================
SM_ARN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text)
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text

# 1-5 Workflow Result (Normal)
echo ====================
echo "  1-5 Workflow Result (Normal)"
echo ====================
aws dynamodb get-item --table-name wsc2026-student-score --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text; aws s3 ls s3://$BUCKET_NAME/processed/

# 1-6 Workflow Result (Error)
echo ====================
echo "  1-6 Workflow Result (Error)"
echo ====================
aws s3 ls s3://$BUCKET_NAME/error/
