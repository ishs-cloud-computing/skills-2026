# set-07 / task-2 — Small Challenge

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-nosql](module-1-nosql/) | NoSQL | ap-southeast-1 | DynamoDB(Streams·GSI) + Lambda + EC2 | CloudShell |
| module-2 (미착수) | CDN Function | us-east-1 | S3 + CloudFront Functions + KVS | - |
| module-3 (미착수) | EKS Scaling | ap-northeast-2 | EKS + KEDA(SQS) + Karpenter | - |
| module-4 (미착수) | Container Logging | ap-northeast-1 | EKS + OTel + Loki + Grafana | - |

## 공통 워크플로

본 PC 단계는 **PowerShell 7 기준**(대회 환경). 본 PC 가 Linux 면 각 모듈의 README.linux.md 를 사용한다.

```powershell
# 각 모듈 디렉터리에서 독립적으로 배포
cd module-<n>-<name>/terraform
terraform init && terraform apply -auto-approve
# 이후 모듈별 README 의 "배포 순서" 를 따른다.
```

공식 채점 스크립트는 `mark/`(mark1~4.sh)에, 제공 배포파일은 `provided/`에 있다. 제공 배포파일은 수정하지 않으며 각 모듈 terraform이 직접 참조한다.

```bash
# 채점 시 기본 리전 설정 (채점지 사전 작업)
aws configure set default.region ap-southeast-1   # module-1
aws configure set default.region us-east-1        # module-2
aws configure set default.region ap-northeast-2   # module-3
aws configure set default.region ap-northeast-1   # module-4
```

## 공통 규칙

- 리소스 이름은 과제지에 명시된 값과 **정확히 일치**(이름 일치 채점 항목 다수).
- SG outbound 80/443 anyopen (유의사항 6). IAM `Principal:"*"`·`Action:"*"` 금지 (유의사항 11).
- EC2 는 명시 없으면 t3.small + Amazon Linux 2023 (유의사항 12).

> 설계 근거·요구사항↔구현 매핑은 docs 사이트(setlist/set-07/task-2)를 참고한다.
