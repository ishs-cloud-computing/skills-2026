# Module 1 — 성적 처리 서버리스 워크플로우 (ap-southeast-1)

S3 `input/` 에 CSV 업로드 → 트리거 Lambda → Step Functions → 처리 Lambda 가 검증/DynamoDB 저장, 오류는 `error/` 에 JSON 저장, 원본은 `processed/` 로 복사. 채점은 CloudShell 에서 `mark/mark2-1.sh` 실행.

> **채점 절차가 RC 판에서 바뀌었다.** test.csv 를 올리는 주체가 선수 → **채점자**다. 채점 시작 시
> 버킷·테이블에 데이터가 남아 있으면 1-1·1-5·1-6 이 모두 오답이므로, 대회 종료 전 3) 단계로
> **완전히 비운 상태**를 만들어 둔다. 리허설(2단계)과 최종 상태(3단계)를 헷갈리지 말 것.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다(CloudShell 단계는 공통).

## 디렉토리 구조

```
module-1-workflow/
└── terraform/
    ├── s3.tf dynamodb.tf lambda.tf stepfunctions.tf iam.tf
    ├── statemachine/workflow.asl.json
    └── lambda/index.py (처리, provided 복사+TODO 완성) · trigger.py (트리거)

# 제공 원본: task-2/provided/module1/ (수정 금지) — test.csv 는 리허설·CloudShell 셀프채점에서 사용.
#   저장소엔 문서만 있다. 배부물 test.csv·lambda-function.py 를 이 경로에 먼저 놓는다 (task-2/README.md)
# 채점: task-2/mark/mark2-1.sh (CloudShell, ap-southeast-1)
```

## 배포 순서

### 1) [본 PC·PowerShell] 배포

`terraform.tfvars` 의 `player_number` 를 본인 등번호로 바꾼 뒤:

```powershell
cd terraform
terraform init
terraform apply
terraform output -json > outputs.json
```

### 2) [본 PC·PowerShell] 리소스 검증 + 리허설

```powershell
$B = terraform output -raw bucket_name   # cwd = terraform (1 단계에 이어짐)
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

# 1-1 버킷 + 폴더 (리허설 후: PRE error/ input/ processed/ 3개만 나와야 함)
aws s3 ls s3://$B/
# 1-2 테이블 + KeySchema
aws dynamodb describe-table --table-name wsc2026-student-score --query "Table.[TableName,KeySchema]" --output json
# 1-3 Lambda 이름/런타임/env
aws lambda get-function-configuration --function-name wsc2026-student-score-function --query "[FunctionName,Runtime,Environment.Variables]" --output json
# 1-4 State Machine 이름/타입
$SM_ARN = aws stepfunctions list-state-machines --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn" --output text
aws stepfunctions describe-state-machine --state-machine-arn $SM_ARN --query "[name,type]" --output text

# 리허설: test.csv 1회 처리 (배부물을 provided/module1/ 에 놓아둔 상태여야 한다)
aws s3 cp ..\..\provided\module1\test.csv s3://$B/input/test.csv
Start-Sleep -Seconds 60   # 과제지: 업로드 시점부터 60초 이내 완료

# 실행 완료 확인 (SUCCEEDED 1건)
aws stepfunctions list-executions --state-machine-arn $SM_ARN --query "executions[].[status,startDate]" --output text

# 결과 확인 = mark 1-5/1-6 그대로
aws dynamodb get-item --table-name wsc2026-student-score --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' --query "Item.[studentId.S,average.N,grade.S]" --output text   # STU1020 96.6 A
aws s3 ls s3://$B/processed/   # test.csv 만
aws s3 ls s3://$B/error/       # error_*_STU2001/STU2002/STU2004/unknown.json 4개만
```

test.csv 를 두 번 올리면 `error/` 에 timestamp 가 다른 JSON 이 8개가 되어 1-6 오답이다. 리허설을
다시 돌리려면 3) 로 완전히 비운 뒤 처음부터 한다.

### 3) [본 PC·PowerShell] 채점 직전 상태 — 버킷·테이블을 완전히 비운다

**과제 종료 전 반드시 실행한다.** 남아 있으면 채점자가 1-1·1-5·1-6 을 모두 오답 처리한다
(과제지 1) Workflow §1·§3). 비운 뒤에는 **아무것도 올리지 않는다** — test.csv 는 채점자가 올린다.

```powershell
# 3-1) 버킷의 모든 객체 삭제 (input/ 포함, 폴더 마커도 없다)
aws s3 rm s3://$B/ --recursive
aws s3 ls s3://$B/ --recursive    # 출력이 비어야 한다

# 3-2) DynamoDB 전체 항목 삭제
$items = aws dynamodb scan --table-name wsc2026-student-score --query "Items[].{studentId:studentId,examDate:examDate}" --output json | ConvertFrom-Json
foreach ($i in $items) {
  $key = $i | ConvertTo-Json -Compress
  aws dynamodb delete-item --table-name wsc2026-student-score --key $key
}
aws dynamodb scan --table-name wsc2026-student-score --select COUNT --query "Count" --output text   # 0 이어야 한다
```

### 4) [CloudShell] 셀프 채점 (선택)

`mark2-1.sh` 은 채점지 1-0 절차를 그대로 흉내낸다 — 클렌징 상태를 보여주고, `test.csv` 를
업로드하고, 60초 기다린 뒤 1-1~1-6 을 찍는다. `mark2-1.sh` 과 `test.csv` 를 함께 올린다.

```bash
sed -i 's/\r$//' mark2-1.sh
bash mark2-1.sh
```

**셀프 채점을 돌렸으면 3) 을 한 번 더 실행해 다시 비워 둔다.**

## Teardown

### [본 PC·PowerShell]

```powershell
cd terraform
terraform destroy
```

## 요구사항 ↔ 구현 매핑

| Mark | 요구 | 구현 |
|---|---|---|
| 1-1 | 버킷 + input/·processed/·error/ | `s3.tf` (마커 객체 없음 — 세 PRE 는 채점자가 올린 input/test.csv 와 산출물로 채워진다) |
| 1-2 | wsc2026-student-score, studentId HASH + examDate RANGE | `dynamodb.tf` |
| 1-3 | wsc2026-student-score-function, python3.12, env S3_BUCKET/DDB_TABLE | `lambda.tf` + `lambda/index.py` |
| 1-4 | wsc2026-student-score-workflow, STANDARD | `stepfunctions.tf` + `statemachine/workflow.asl.json` |
| 1-5 | STU1020 = 96.6 / A, processed/에 test.csv만 | `index.py` Decimal 평균 + ASL MoveToProcessed |
| 1-6 | error/에 error_*.json 정확히 4개 | `index.py` save_error (STU2001·STU2002·STU2004·unknown) |
| 6. Workflow 구성 | CheckS3File→ProcessStudentData→CheckResult→MoveToProcessed/MoveToError, 트리거 Lambda, `{"key": …}` 입력 | `statemachine/workflow.asl.json` + `lambda/trigger.py` |
| IAM | 최소권한 역할 2개 | `iam.tf` (wsc2026-lambda-student-role / wsc2026-stepfunction-student-role) |

## 설계 근거 · 함정

- 처리 Lambda 이름 `wsc2026-student-score-function` 은 RC 판 과제지 §2 와 채점 1-3 이 함께 못 박는다 — 변경 금지.
- **S3 폴더 마커 객체를 만들지 않는다.** RC 판이 "채점 시작시 버킷의 데이터가 삭제되어 있는지 확인" 을 요구하는데 0바이트 마커도 잔존 데이터로 잡힐 수 있다. 마커 없이도 1-1 의 세 PRE 는 채점자가 올린 `input/test.csv` 와 산출물(`processed/`·`error/`)로 채워진다.
- **워크플로우가 input 객체를 지우지 않는다.** 지우면 `PRE input/` 이 사라져 1-1 이 깨진다. 그래서 `MoveToProcessed`·`MoveToError` 는 copy 만 하고 바로 End/Fail 로 간다 — 과제지 6. Workflow 구성 플로우도와 상태 구성이 정확히 같아진다. sfn 역할에 `s3:DeleteObject` 도 주지 않는다.
- **평균은 Decimal 나눗셈** (`Decimal("483")/Decimal("5")` = 정확히 96.6). float는 96.60000000000001이 되고 boto3가 float 저장을 거부한다.
- **PowerShell 7.3+ 에서 JSON 인자는 작은따옴표로만 감싼다** — 따옴표가 그대로 전달된다. PS 5.1 식 `\"` 이스케이프를 하면 백슬래시가 그대로 들어가 aws cli 파싱 오류가 난다.
- 트리거 suffix가 `.csv`라 Lambda가 error/에 쓰는 `.json`으로는 재귀 트리거되지 않는다.
- 처리 Lambda는 State Machine에서 ARN 직접 호출 — 출력이 `$.result`에 그대로 실려 `.Payload` 언랩 불필요.
- 두 Lambda는 `wsc2026-lambda-student-role` 공용 (과제가 Lambda 역할을 하나만 명명).
