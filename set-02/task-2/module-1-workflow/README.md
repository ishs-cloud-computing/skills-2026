# module-1-workflow — 성적 처리 서버리스 워크플로우 (ap-southeast-1)

S3 `input/`에 CSV 업로드 → 트리거 Lambda → Step Functions → 처리 Lambda가 검증/DynamoDB 저장, 오류는 `error/`에 JSON 저장, 완료 후 파일을 `processed/`로 이동.

```
module-1-workflow/
└── terraform/
    ├── s3.tf dynamodb.tf lambda.tf stepfunctions.tf iam.tf
    ├── statemachine/workflow.asl.json
    └── lambda/index.py (처리, provided 복사+TODO 완성) · trigger.py (트리거)
```

## 배포 (본 PC, PowerShell)

```powershell
cd module-1-workflow\terraform
terraform init
terraform apply -var "player_number=$env:NUM"
terraform output -json > outputs.json
```

## 리소스 검증 (본 PC, PowerShell)

PowerShell에서 JSON 인자는 내부 따옴표를 `\"`로 이스케이프해야 aws cli에 온전히 전달된다.

```powershell
$NUM = $env:NUM
$B = "wsc2026-student-score-bucket-$NUM"
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

# 1-1 버킷 + 폴더 (PRE error/ input/ processed/ 만 나와야 함 — 최종 실행 후)
aws s3 ls s3://$B/
# 1-2 테이블 + KeySchema
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
# 1-3 Lambda 이름/런타임/env
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
# 1-4 State Machine 이름/타입
$SM_ARN = aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text
```

## 최종 실행 절차 (본 PC, PowerShell — 채점 직전, 순서 엄수)

채점 상태 = "깨끗한 버킷/테이블에서 test.csv 1회 처리 완료" 상태여야 한다.

```powershell
# 1) 이전 실행 잔여물 제거 (processed/·error/ 에 잉여 파일 있으면 1-5-A/B 오답)
aws s3 rm s3://$B/processed/ --recursive
aws s3 rm s3://$B/error/ --recursive

# 2) DynamoDB 비우기 (과제지: 채점 시작 시 테이블은 비어 있어야 함)
$items = aws dynamodb scan --table-name wsc2026-student-score --query "Items[].{studentId:studentId,examDate:examDate}" --output json | ConvertFrom-Json
foreach ($i in $items) {
  $key = ($i | ConvertTo-Json -Compress) -replace '"', '\"'
  aws dynamodb delete-item --table-name wsc2026-student-score --key $key
}

# 3) test.csv 업로드 → 워크플로우 자동 실행 (본 PC에는 provided 원본이 있다)
aws s3 cp ..\..\provided\module1\test.csv s3://$B/input/test.csv

# 4) 실행 완료 확인 (SUCCEEDED 1건)
aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text

# 5) 결과 확인 = mark 1-5-A/B 그대로
aws dynamodb get-item --table-name wsc2026-student-score --key '{\"studentId\":{\"S\":\"STU1020\"},\"examDate\":{\"S\":\"2026-05-30\"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # error_*_STU2001/STU2002/STU2004/unknown.json 4개만
```

test.csv를 두 번 업로드하면 error/에 timestamp가 다른 JSON이 8개가 되어 1-5-B 오답 — 재실행하려면 반드시 1)~2)부터 다시.

## Linux 런북 (개인 리눅스 환경용 — 대회에서는 PowerShell 런북 사용)

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

## 요구사항 ↔ 구현 매핑

| Mark | 요구 | 구현 |
|---|---|---|
| 1-1 | 버킷 + input/·processed/·error/ | `s3.tf` (마커는 input/ 하나만) |
| 1-2 | wsc2026-student-score, studentId HASH + examDate RANGE | `dynamodb.tf` |
| 1-3 | wsc2026-student-score-function, python3.12, env S3_BUCKET/DDB_TABLE | `lambda.tf` + `lambda/index.py` |
| 1-4 | wsc2026-student-score-workflow, STANDARD | `stepfunctions.tf` + `statemachine/workflow.asl.json` |
| 1-5-A | STU1020 = 96.6 / A, processed/에 test.csv만 | `index.py` Decimal 평균 + ASL MoveToProcessed |
| 1-5-B | error/에 error_*.json 정확히 4개 | `index.py` save_error (STU2001·STU2002·STU2004·unknown) |
| IAM | 최소권한 역할 2개 | `iam.tf` (wsc2026-lambda-student-role / wsc2026-stepfunction-student-role) |

## 설계 근거 · 함정

- **처리 Lambda 이름 `wsc2026-student-score-function`은 task.md에 없고 mark 1-3에만 등장** — 이름 변경 금지.
- **S3 폴더 마커는 `input/` 하나만 생성.** 채점 시 processed/·error/에는 실제 객체가 있어 PRE가 뜨고, 마커를 만들면 1-5-A/B 목록에 잉여 0바이트 라인이 출력돼 오답. input/은 워크플로우가 파일을 옮겨가 비므로 마커 필요.
- **평균은 Decimal 나눗셈** (`Decimal("483")/Decimal("5")` = 정확히 96.6). float는 96.60000000000001이 되고 boto3가 float 저장을 거부한다.
- **PowerShell(5.1)에서 JSON 인자는 `\"` 이스케이프 필수** — 그냥 작은따옴표로 감싸면 내부 큰따옴표가 벗겨져 aws cli 파싱 오류가 난다.
- 트리거 suffix가 `.csv`라 Lambda가 error/에 쓰는 `.json`으로는 재귀 트리거되지 않는다.
- Step Functions의 Copy+Delete는 API가 2개라 상태도 2개(`MoveToProcessed`→`DeleteInputProcessed`)로 분리 — 채점은 [name,type]과 S3/DDB 최종 상태만 본다.
- 처리 Lambda는 State Machine에서 ARN 직접 호출 — 출력이 `$.result`에 그대로 실려 `.Payload` 언랩 불필요.
- 두 Lambda는 `wsc2026-lambda-student-role` 공용 (과제가 Lambda 역할을 하나만 명명).
