# Module 4 — REST API Implement (us-east-1)

API Gateway(REST) + Lambda(Python 3.14) + DynamoDB로 Serverless REST API를 구성한다. 채점은 CloudShell에서 수행한다.

## 디렉토리 구조

```
module-4-rest-api/
├── terraform/
│   ├── dynamodb.tf   # wsc-rest-table (PK name, On-Demand)
│   ├── lambda.tf     # wsc-rest-function (python3.14)
│   ├── lambda/index.py
│   ├── apigw.tf      # wsc-rest-api, prod, API Key, MOCK healthcheck, 검증
│   └── outputs.tf
└── README.md

(채점: task-2/mark/mark4.sh — 공식 채점 스크립트, CloudShell 에서 실행)

## API 동작

| Path | Method | 인증 | 동작 |
|------|--------|------|------|
| /v1/user | POST | API Key | body 검증 → Conditional Put → 생성/중복 |
| /v1/user | GET | API Key | querystring name·age 검증 → 조회 |
| /v1/healthcheck | GET | 없음 | MOCK → `{"status":"ok"}` |

- 중복 저장 방지: DynamoDB `ConditionExpression=attribute_not_exists(name)` → 재시도에도 멱등, 중복 시 `{"message": "User already exists"}`.
- API Key 없음 → 403 `{"message":"Forbidden"}` (기본 Gateway Response).
- querystring 검증 실패(age 누락) → 400 `{"message": "Missing required request parameters: [age]"}` (Lambda 미도달).

## 배포 순서

```bash
cd terraform
terraform init && terraform apply -auto-approve

# 셀프 채점 (CloudShell) — 공식 채점 스크립트 (task-2/mark/)
cd ..
bash ../mark/mark4.sh
```

## 요구사항 ↔ 구현 매핑 (채점지 4)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 4-1 | 인프라(API GW/Lambda/DynamoDB) | `apigw.tf`,`lambda.tf`,`dynamodb.tf` |
| 4-2 | healthcheck (MOCK) | `apigw.tf` healthcheck MOCK |
| 4-3 | /v1/user POST·GET | `lambda/index.py` + `apigw.tf` |
| 4-4 | 중복 저장 방지 | `lambda/index.py` Conditional Put |
| 4-5 | API Key 인증 차단 | `apigw.tf` api_key_required + usage plan |
| 4-6 | 잘못된 요청 차단 | `apigw.tf` request_validator + gateway_response |

## 주의 / 검증 포인트

- **이름 정확 일치**: API `wsc-rest-api`, stage `prod`, Lambda `wsc-rest-function`(Runtime `python3.14`), Table `wsc-rest-table`, API Key `wsc-rest-api-key`.
- `/v1/healthcheck` 는 **Lambda에서 개발하지 않고** MOCK 통합으로만 처리한다. 응답 `{"status":"ok"}`(공백 없음)은 MOCK 응답 템플릿으로 정확히 제어.
- GET 응답은 `{"name": "kim", "country": "korea", "age": 19}` 순서/타입(age는 Number)으로 반환한다. boto3 Decimal → int 변환.
- `BAD_REQUEST_PARAMETERS` Gateway Response를 커스터마이즈하여 `{"message": "Missing required request parameters: [age]"}`(공백 포함)으로 표기 일치.
- Exception 시 Stack Trace를 노출하지 않고 `{"message": "Internal server error"}` 반환. boto3 resource/table은 모듈 스코프 재사용.
- DynamoDB는 `PAY_PER_REQUEST`(On-Demand)로 3000 RPS Burst에 대응하며, `name`을 PK로 사용해 Hot Partition 위험을 낮춘다.
