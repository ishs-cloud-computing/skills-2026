# set-08 / task-2 — Small Challenges

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-nosql](module-1-nosql/README.md) | NoSQL | ap-northeast-2 | DocumentDB + EC2 Client | CloudShell (`mark2-1.sh`) |
| [module-2-lattice](module-2-lattice/README.md) | VPC Lattice | ap-northeast-1 | EC2 ×2 + VPC Lattice | CloudShell (`mark2-2.sh`) |
| [module-3-event-handling](module-3-event-handling/README.md) | Cloud Event Handling | ap-southeast-1 | EventBridge + Lambda + SNS | CloudShell (`mark2-3.sh`) |
| [module-4-sqs-scaling](module-4-sqs-scaling/README.md) | SQS Scaling | us-west-2 | EKS(Fargate) + KEDA(SQS) + Karpenter | CloudShell (`mark2-4.sh`) |

각 모듈의 배포·채점·teardown 절차는 해당 모듈 README(런북)를 따른다. 여기서는 절차를 반복하지 않고 모듈 간 공통 사항만 다룬다.

## 공통 워크플로

```powershell
# 각 모듈 디렉터리에서 독립적으로 배포
terraform -chdir=module-<n>-<name>/terraform init
terraform -chdir=module-<n>-<name>/terraform apply -auto-approve
# 이후 모듈별 README 의 배포 절차를 따른다.
```

module-4(EKS)는 클러스터가 하나이므로 **모듈 전용 터미널**에서 kubeconfig를 모듈 경로로 고정하고 시작한다(터미널 1개 = 클러스터 1개):

```powershell
cd module-4-sqs-scaling
$env:KUBECONFIG = "$PWD\kubeconfig"
```

공식 채점 스크립트는 `mark/`(mark2-1~4.sh)에, 제공 배포파일은 `provided/`에 있다. 제공 배포파일은 수정하지 않으며 각 모듈 terraform/eksctl이 직접 참조한다. 채점은 CloudShell에서 실행한다 — 저장소가 private이라 git clone은 안 되므로 **작업 → 파일 업로드**로 전송하고(CloudShell 홈은 리전별로 분리, 업로드는 `$HOME`에 평평하게 저장), 실행 전 CRLF 가드를 거친다:

```bash
sed -i 's/\r$//' <스크립트_파일명>
```

## 공통 규칙

- 리소스 이름·태그는 과제지에 명시된 값과 **정확히 일치**(이름 일치 채점 항목 다수).
- `.env`(본 PC용 `.env.ps1`, CloudShell 업로드용 `.env`)는 `terraform output` 직후 생성한다. 둘 다 gitignore 대상 — 재부팅·CloudShell 세션 초기화 시 재생성/재업로드.
- module-4는 로컬에 Docker가 없어 이미지 build/push가 CloudShell 필수 경로다. mark 스크립트도 `jq` 의존이라 로컬 대체 실행이 불가 — CloudShell 접속을 0단계에서 먼저 확인한다.
- CloudShell 진입 시 활성 탭이 이전 세션의 VPC 환경이면 파일 업로드가 막힌다. 기본 리전 탭으로 전환한다.

> 트랩·원인은 [NOTES.md](NOTES.md) 함정 절, 런북 개선 이력은 [FEEDBACK.md](FEEDBACK.md) 참고.

## 실행 순서 (대기 시간 기준)

4모듈의 `terraform apply`는 서로 완전히 독립이므로 **처음에 4개를 전부 걸어두고** 대기 구간에 검증·채점을 순서대로 처리한다. 터미널 4개(모듈별 1개)를 동시에 연다.

1. **0단계 선행 체크**: CloudShell 접속 확인(module-4 README 0단계).
2. **4모듈 `terraform apply` 전부 시작**. 실측 소요: module-3 ~1분 / module-2 ~2분 / module-4 ~3분 / module-1 ~7분(DocumentDB 인스턴스 병목).
3. **module-4 eksctl create cluster 시작** (terraform apply 직후, **~19분**으로 전체 최장 경로). 별도 창에서 실행하고 로그 파일로 진행을 확인한다.
4. eksctl 대기 중 CloudShell에서 워커 이미지 build/push 진행 (module-4 README 3단계 — 병렬 처리 설계).
5. **module-2 검증 + 채점** (대기 짧음).
6. **module-3 검증 + 채점** (실경로 복구 실측 ~20초).
7. **module-1 검증 + 채점**.
8. module-4 클러스터 준비 후 helm → k8s manifest apply → 스케일 검증 → 채점 (module-4 README 4단계 이후). `mark2-4.sh`만 실행에 **~11분** 걸리니 시간을 따로 잡는다.
9. 채점 직전: module-4 경량 상태 확인 (README 8단계, purge 금지).

> 설계 근거·요구사항↔구현 매핑은 docs 사이트(setlist/set-08/task-2)를 참고한다.
