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
- **CloudShell 전송은 업로드만**: 저장소가 private이라 CloudShell에서 `git clone`이 안 된다(익명 clone 404). 전송은 **작업 → 파일 업로드**로 통일한다. 업로드 파일은 항상 `$HOME`(`/home/cloudshell-user`)에 평평하게 떨어지므로 실행 명령도 `bash mark2-N.sh`처럼 홈 기준으로 친다.
- **CloudShell 홈은 리전별로 분리**: 모듈마다 리전이 다르므로 mark 스크립트를 리전마다 다시 업로드해야 한다. 한 리전에 올린 파일은 다른 리전 CloudShell에 없다.
- **CloudShell 진입 시 활성 탭 확인**: 이전 세션에서 만든 VPC 환경 탭이 활성 상태로 복원되면 작업 메뉴의 파일 업로드/다운로드가 비활성(`File transfer isn't available for VPC environments`)이라 전송이 막힌다. 기본 리전 탭으로 전환한 뒤 진행한다.
- **채점은 사실상 CloudShell 전용**: mark 스크립트는 `jq`에 의존하는데 본 PC(Windows Git Bash)에는 `jq`가 없다. 로컬 대체 실행 경로가 없으므로 CloudShell 접속을 0단계에서 먼저 확인한다(module-4는 Docker가 로컬에 없어 이미지 build/push도 CloudShell 필수 — 접속 실패 시 module-4 전체가 막힌다).
- **EKS 모듈(module-4)은 모듈 전용 터미널**: kubeconfig를 모듈 경로로 고정하고 시작한다(터미널 1개 = 클러스터 1개). 재부팅 후엔 모듈 README의 복구 절차를 따른다.
- **`provided/`는 원본 그대로**: `provided/module-N/*`는 대회 제공 원본이며 수정하지 않는다. 각 모듈 terraform/eksctl이 직접 참조한다.

## 실행 순서 (대기 시간 기준)

4모듈의 `terraform apply`는 서로 완전히 독립이므로 **처음에 4개를 전부 걸어두고** 대기 구간에 검증·채점을 순서대로 처리한다. 터미널 4개(모듈별 1개)를 동시에 연다.

1. **0단계 선행 체크**: IAM 권한 프로브 1회(module-4 README 0단계) + CloudShell 접속 확인.
2. **4모듈 `terraform apply` 전부 시작**. 실측 소요: module-3 ~1분 / module-2 ~2분 / module-4 ~3분 / module-1 ~7분(DocumentDB 인스턴스 병목).
3. **module-4 eksctl create cluster 시작** (terraform apply 직후, **~19분**으로 전체 최장 경로). 별도 창에서 실행하고 로그 파일로 진행을 확인한다.
4. eksctl 대기 중 CloudShell에서 워커 이미지 build/push 진행 (module-4 README 3단계 — 병렬 처리 설계).
5. **module-2 검증 + 채점** (대기 짧음).
6. **module-3 검증 + 채점** (실경로 복구 실측 ~20초).
7. **module-1 검증 + 채점**.
8. module-4 클러스터 준비 후 helm → k8s manifest apply → 스케일 검증 → 채점 (module-4 README 4단계 이후). `mark2-4.sh`만 실행에 **~11분** 걸리니 시간을 따로 잡는다.
9. 채점 직전: module-4 경량 상태 확인 (README 8단계, purge 금지).

> 설계 근거·요구사항↔구현 매핑은 docs 사이트(setlist/set-08/task-2)를 참고한다.
