# Module 1 — 성적 처리 서버리스 워크플로우 (ap-southeast-1)

S3 `input/` 에 CSV 업로드 → 트리거 Lambda → Step Functions → 처리 Lambda 가 검증/DynamoDB 저장, 오류는 `error/` 에 JSON 저장, 완료 후 파일을 `processed/` 로 이동. 채점은 CloudShell 에서 `mark/mark2-1.sh` 실행.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-1-workflow/
└── terraform/
    ├── s3.tf dynamodb.tf lambda.tf stepfunctions.tf iam.tf
    ├── statemachine/workflow.asl.json
    └── lambda/index.py (처리, provided 복사+TODO 완성) · trigger.py (트리거)

# 제공 원본: task-2/provided/module1/ (수정 금지) — test.csv 는 최종 실행에서 사용
# 채점: task-2/mark/mark2-1.sh (CloudShell, ap-southeast-1)
```

## 배포 순서

### 1) [본 PC·PowerShell] 배포

`terraform.tfvars` 의 `player_number` 를 본인 비번호로 바꾼 뒤:

```powershell
cd terraform
terraform init
terraform apply
terraform output -json > outputs.json
```

### 2) [본 PC·PowerShell] 리소스 검증

```powershell
$B = terraform output -raw bucket_name   # cwd = terraform (1 단계에 이어짐)
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

### 3) [본 PC·PowerShell] 최종 실행 — 채점 직전, 순서 엄수

채점 상태 = "깨끗한 버킷/테이블에서 test.csv 1회 처리 완료" 상태여야 한다.

```powershell
# 3-1) 이전 실행 잔여물 제거 (processed/·error/ 에 잉여 파일 있으면 1-5-A/B 오답)
aws s3 rm s3://$B/processed/ --recursive
aws s3 rm s3://$B/error/ --recursive

# 3-2) DynamoDB 비우기 (과제지: 채점 시작 시 테이블은 비어 있어야 함)
$items = aws dynamodb scan --table-name wsc2026-student-score --query "Items[].{studentId:studentId,examDate:examDate}" --output json | ConvertFrom-Json
foreach ($i in $items) {
  $key = $i | ConvertTo-Json -Compress
  aws dynamodb delete-item --table-name wsc2026-student-score --key $key
}

# 3-3) test.csv 업로드 → 워크플로우 자동 실행 (본 PC 에는 provided 원본이 있다)
aws s3 cp ..\..\provided\module1\test.csv s3://$B/input/test.csv

# 3-4) 실행 완료 확인 (SUCCEEDED 1건)
aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text

# 3-5) 결과 확인 = mark 1-5-A/B 그대로
aws dynamodb get-item --table-name wsc2026-student-score --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # error_*_STU2001/STU2002/STU2004/unknown.json 4개만
```

test.csv 를 두 번 업로드하면 `error/` 에 timestamp 가 다른 JSON 이 8개가 되어 1-5-B 오답 — 재실행하려면 반드시 3-1)~3-2) 부터 다시.

### 4) [CloudShell] 셀프 채점

```bash
sed -i 's/\r$//' mark2-1.sh
bash mark2-1.sh
```

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy
```

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
- **PowerShell 7.3+ 에서 JSON 인자는 작은따옴표로만 감싼다** — 따옴표가 그대로 전달된다. PS 5.1 식 `\"` 이스케이프를 하면 백슬래시가 그대로 들어가 aws cli 파싱 오류가 난다.
- 트리거 suffix가 `.csv`라 Lambda가 error/에 쓰는 `.json`으로는 재귀 트리거되지 않는다.
- Step Functions의 Copy+Delete는 API가 2개라 상태도 2개(`MoveToProcessed`→`DeleteInputProcessed`)로 분리 — 채점은 [name,type]과 S3/DDB 최종 상태만 본다.
- 처리 Lambda는 State Machine에서 ARN 직접 호출 — 출력이 `$.result`에 그대로 실려 `.Payload` 언랩 불필요.
- 두 Lambda는 `wsc2026-lambda-student-role` 공용 (과제가 Lambda 역할을 하나만 명명).
