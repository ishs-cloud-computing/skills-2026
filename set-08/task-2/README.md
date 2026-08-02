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

### 1. 작업 시작 전 필수 체크
* **리전 확인**: 새 모듈 작업 전 반드시 리전 확인 (리전 오류 시 0점 처리)
  ```powershell
  # 로컬(Windows) 확인 명령어
  aws configure get region
  $env:AWS_DEFAULT_REGION
  ```
* **CloudShell 탭 확인**: 파일 업로드/다운로드 버튼이 막혀있다면, **VPC 환경 탭에서 기본 리전 탭으로 전환**
* **CloudShell 접속 확인**: module-4는 로컬에 Docker가 없어 이미지 build/push가 CloudShell 필수 경로다. mark 스크립트도 `jq`에 의존해 로컬(Windows Git Bash) 대체 실행이 불가하다 — 접속 실패 시 진행 자체가 막히므로 0단계에서 먼저 확인
* **EKS 전용 터미널 고정**: module-4(EKS) 작업 시, 터미널 1개당 클러스터 1개만 연결되도록 **kubeconfig 경로를 모듈 경로로 고정**하고 시작

### 2. 리소스 생성 및 파일 규칙
* **이름/태그 정확히 일치**: 과제지에 명시된 이름과 태그를 토씨 하나 틀리지 않고 그대로 사용 (채점 항목)
* **`provided/`는 원본 그대로**: `provided/module-N/*`는 대회 제공 원본이며 수정하지 않는다. 각 모듈 terraform/eksctl이 직접 참조한다.
* **`.env` 즉시 생성**: `terraform output` 직후 아래 2개 파일 생성 (**둘 다 gitignore 필수**)
  * 로컬 PC용 (PowerShell 변수 복원): `.env.ps1`
  * CloudShell용 (bash export): `.env`

### 3. CloudShell 채점 (mark/) 실행 규칙
* **전송은 업로드만**: 저장소가 private이라 CloudShell에서 `git clone`이 안 된다(익명 clone 404). **작업 → 파일 업로드**로만 전송한다.
* **업로드는 홈 기준**: 업로드 파일은 항상 `$HOME`(`/home/cloudshell-user`)에 평평하게 떨어지므로 실행 명령도 `bash mark2-N.sh`처럼 홈 기준으로 친다.
* **리전별 개별 업로드**: CloudShell 홈은 리전별로 분리되어 있으므로, **모듈 변경 시 해당 리전 CloudShell에 mark 스크립트 새로 업로드**
* **줄바꿈(CRLF) 에러 가드**: Windows에서 작성한 파일을 CloudShell에 올린 후, 실행 전 **반드시 아래 명령어로 파일 변환**
  ```bash
  sed -i 's/\r$//' <스크립트_파일명>
  ```

### 4. 재부팅 및 세션 초기화 복구
* **로컬 PC 재부팅 시**: `.env.ps1`을 실행하여 PowerShell 세션 변수 복원 (EKS는 모듈 README 복구 절차 수행)
* **CloudShell 세션 초기화 시**: `.env` 및 채점 스크립트 재업로드 진행

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
