# set-02 / task-2

4개 독립 모듈로 구성된 2과제. 모듈별 리전이 다르므로 apply 전 리전을 반드시 확인한다.

| 모듈 | 주제 | 리전 | 주요 서비스 | 상태 |
|---|---|---|---|---|
| [module-1-workflow](module-1-workflow/) | 성적 처리 서버리스 워크플로우 | ap-southeast-1 | S3, Lambda, DynamoDB, Step Functions | 구현 완료 |
| [module-2-analytics](module-2-analytics/) | 실시간 주문 로그 분석 | ap-northeast-2 | VPC, EC2, ALB, Kinesis, Managed Flink Studio | 구현 완료 |
| module-3 | Cloud event handling | - | - | 미구현 |
| module-4 | MSK | - | - | 미구현 |

## 공통 워크플로

```powershell
cd <module-N-...>/terraform
terraform init
terraform apply -var "player_number=$env:NUM"
```

- 각 모듈은 독립 terraform 루트 — 모듈 순서 무관, 병렬 배포 가능.
- 채점 스크립트: `mark/mark2-<모듈번호>.sh` (Bastion 또는 CloudShell에서 실행).
- `provided/`는 대회 제공 원본 — 수정 금지. 구현에 필요한 소스는 각 모듈 디렉토리에 복사/참조되어 있다.
- 세부 배포·검증 절차는 각 모듈 README 런북을 따른다 — 대회 본 PC용 PowerShell 런북이 기본이고, 개인 리눅스 환경용 Linux 런북이 함께 있다(bastion/CloudShell에서도 동일 동작).
