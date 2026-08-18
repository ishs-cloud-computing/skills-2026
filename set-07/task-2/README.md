# set-07 / task-2 — Small Challenge

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-nosql](module-1-nosql/) | NoSQL | ap-southeast-1 | DynamoDB(Streams·GSI) + Lambda + EC2 | CloudShell |
| [module-2-cdn-function](module-2-cdn-function/) | CDN Function | us-east-1 | S3 + CloudFront Functions + KVS | CloudShell |
| [module-3-eks-scaling](module-3-eks-scaling/) | EKS Scaling | ap-northeast-2 | EKS + KEDA(SQS) + Karpenter | CloudShell |
| [module-4-container-logging](module-4-container-logging/) | Container Logging | ap-northeast-1 | EKS + OTel + Loki + Grafana | CloudShell |

> **대회 당일에는 [DAY-OF.md](../../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로,
> 아래 값 대조표로 종이 과제지를 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.

## 값 대조표 (당일 종이 과제지 대조용)

| 모듈 | 리전 | 준비본 이름·값 | CIDR |
|---|---|---|---|
| module-1-nosql | `ap-southeast-1` | 테이블 `bigbae-nosql-reservation-table`·`bigbae-nosql-audit-table` / GSI `gsi-user-reservations` / Lambda `bigbae-nosql-reservation-audit` / EC2 `bigbae-nosql-app-ec2`(`t3.small`) | `10.0.0.0/16` (서브넷 `10.0.0.0/24`) |
| module-2-cdn-function | `us-east-1` | 버킷 접두 `skillsphone-landing-ab-` / KVS `skillsphone-cdn-ab-config` / Function `-req-fn`·`-res-fn` / 배포 `skillsphone-cdn-ab-distribution` / 쿠키 `x-sp-ab` / 가중치 `0.3` / 경로 `/version-a/index.html`·`/version-b/index.html` | — |
| module-3-eks-scaling | `ap-northeast-2` | 클러스터 `skm-eks-cluster` / SQS `skm-order-queue` / ECR `skm-order-processor` / 접두 `skm-eks` | `10.13.0.0/16` |
| module-4-container-logging | `ap-northeast-1` | 클러스터 `o11y-cluster` / ECR `o11y-log-generator` / ALB `o11y-app-alb`·`o11y-grafana-alb` / 포트 `8080`·`3000` / 헬스 `/healthz`·`/api/health` | `10.14.0.0/16` |

⚠ **module-2**: 쿠키명·헤더명·KVS 키명이 CloudFront Function 의 **JS 안 리터럴**이라 변수화돼 있지 않다. 이름이 바뀌면 함수 코드를 직접 고친다.

⚠ **module-4**: Grafana 패널의 Loki 라인 필터 `"log generated"` 는 **지급 `app.py` 의 msg 리터럴**이다. 당일 앱이 바뀌어 msg 가 달라지면 필터도 같이 고친다.

## 공통 워크플로

**본 PC 는 `terraform` 과 `eksctl` 만 쓴다.** 이미지 빌드·helm·kubectl·검증·스모크·셀프 채점은 전부 CloudShell 에서 한다 —
채점이 선수의 일반 CloudShell 에서 `aws eks update-kubeconfig` 한 줄로 진행되므로, 그 경로를 배포 초반에 밟아 두어야 k8s 채점 항목이 통째로 날아가는 사고를 막는다.

본 PC 단계는 **PowerShell 7 기준**(대회 환경). 본 PC 가 Linux 면 각 모듈의 README.linux.md 를 사용한다.

```powershell
# 각 모듈 디렉터리에서 독립적으로 배포
cd module-<n>-<name>/terraform
terraform init && terraform apply -auto-approve
# 이후 모듈별 README 의 "배포 순서" 를 따른다.
```

EKS 모듈(3·4)은 클러스터가 각각 있으므로 **모듈 전용 터미널**에서 kubeconfig를 모듈 경로로 고정하고 시작한다
(터미널 1개 = 클러스터 1개 — 엉뚱한 클러스터에 eksctl 을 거는 사고를 원천 차단):

```powershell
cd module-<n>-<name>
$env:KUBECONFIG = "$PWD\kubeconfig"   # eksctl 전용. kubectl·helm 은 CloudShell 에서 쓴다
```

CloudShell 쪽은 홈이 **리전별로 분리**돼 있어 모듈 간 격리가 자동으로 된다. 대신 helm 설치·파일 업로드도 모듈(리전)마다 따로 해야 한다.
CloudShell 기본 탑재는 `aws`·`kubectl`·`docker`·`jq` 이고 **helm 은 없다** — 각 EKS 모듈의 `cs-deploy.sh` 가 `$HOME/bin` 에 설치한다(`$HOME` 밖은 세션 종료 시 삭제).

공식 채점 스크립트는 `mark/`(mark1~4.sh)에, 제공 배포파일은 `provided/`에 있다. 제공 배포파일은 수정하지 않으며 각 모듈 terraform이 직접 참조한다.
저장소가 private이라 `git clone`은 안 되므로 **작업 → 파일 업로드**로 전송한다(module-1·2 는 mark 스크립트 1개, module-3·4 는 README 0·1단계에서 만드는 zip 1개).
업로드는 `$HOME`에 평평하게 저장되므로 실행 경로에 `mark/` 를 붙이지 않는다. Windows 업로드는 실행 전 CRLF 가드를 거친다:

```bash
sed -i 's/\r$//' <스크립트_파일명>
```

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
