# set-08 / task-2 — Small Challenges

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-nosql](module-1-nosql/README.md) | NoSQL | ap-northeast-2 | DocumentDB + EC2 Client | CloudShell (`mark2-1.sh`) |
| [module-2-lattice](module-2-lattice/README.md) | VPC Lattice | ap-northeast-1 | EC2 ×2 + VPC Lattice | CloudShell (`mark2-2.sh`) |
| [module-3-event-handling](module-3-event-handling/README.md) | Cloud Event Handling | ap-southeast-1 | EventBridge + Lambda + SNS | CloudShell (`mark2-3.sh`) |
| [module-4-sqs-scaling](module-4-sqs-scaling/README.md) | SQS Scaling | us-west-2 | EKS(Fargate) + KEDA(SQS) + Karpenter | CloudShell (`mark2-4.sh`) |

각 모듈의 배포·채점·teardown 절차는 해당 모듈 README(런북)를 따른다. 여기서는 절차를 반복하지 않고 모듈 간 공통 사항만 다룬다.

## 공통 규칙

- **리전 4개**: 모듈별로 리전이 다르다(위 표 참조). 유의사항 9에 따라 리전이 잘못되면 해당 모듈이 0점 처리될 수 있으므로, 각 모듈 작업 전 `aws configure get region`/`$env:AWS_DEFAULT_REGION`으로 항상 확인한다.
- **리소스 이름 정확 일치**: 과제지에 명시된 이름·태그를 그대로 사용한다(이름 일치 채점 항목 다수).
- **`.env` 규칙**: 각 모듈은 본 PC용 `.env.ps1`(PowerShell 세션 변수 복원)과 CloudShell 업로드용 `.env`(bash `export`)를 terraform output 직후 생성한다(모듈 README 참고). 둘 다 gitignore 대상이며, 재부팅·CloudShell 세션 초기화 시 재생성 또는 재업로드가 필요하다.
- **`mark/` 실행은 CloudShell**: 채점 스크립트(`mark/mark2-N.sh`)는 CloudShell에서 실행한다. 로컬(Windows)에서 작성한 배포 파일·mark 스크립트를 CloudShell에 업로드할 때는 CRLF가 섞일 수 있어 실행 전 `sed -i 's/\r$//' <파일>` 가드를 거친다.
- **EKS 모듈(module-4)은 모듈 전용 터미널**: kubeconfig를 모듈 경로로 고정하고 시작한다(터미널 1개 = 클러스터 1개). 재부팅 후엔 모듈 README의 복구 절차를 따른다.
- **`provided/`는 원본 그대로**: `provided/module-N/*`는 대회 제공 원본이며 수정하지 않는다. 각 모듈 terraform/eksctl이 직접 참조한다.

## 실행 순서 (대기 시간 기준)

apply 소요 시간이 긴 모듈부터 먼저 걸어두고, 대기 구간에 짧은 모듈을 처리한다. 터미널 4개(모듈별 1개)를 동시에 연다.

1. **module-4 apply 시작** (`terraform apply` — EKS 클러스터 생성 ~15-20분, 가장 오래 걸림). 0단계 IAM 권한 프로브도 이 시점에 1회 실행.
2. **module-1 apply 시작** (DocumentDB 인스턴스 생성 ~10-15분).
3. module-4 대기 중 CloudShell에서 워커 이미지 build/push 진행 (module-4 README 3단계 — 병렬 처리 설계).
4. **module-2 apply + 검증 + 채점** (전체 apply 한 번으로 끝, 대기 짧음).
5. **module-3 apply + 검증 + 채점** (apply 짧음, 검증 2는 이벤트 전달 대기 수 분).
6. module-1 완료 확인 후 검증 + 채점.
7. module-4 완료 확인 후 k8s manifest apply + 검증 + 채점 (module-4 README 4단계 이후).
8. 채점 직전: module-4 min 0 스케일 사전 활성화 (README 8단계, purge 금지).

> 설계 근거·요구사항↔구현 매핑은 docs 사이트(setlist/set-08/task-2)를 참고한다.
