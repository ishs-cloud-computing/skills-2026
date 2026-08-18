# set-08 / task-2 — Small Challenges

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-nosql](module-1-nosql/README.md) | NoSQL | ap-northeast-2 | DocumentDB + EC2 Client | CloudShell (`mark2-1.sh`) |
| [module-2-lattice](module-2-lattice/README.md) | VPC Lattice | ap-northeast-1 | EC2 ×2 + VPC Lattice | CloudShell (`mark2-2.sh`) |
| [module-3-event-handling](module-3-event-handling/README.md) | Cloud Event Handling | ap-southeast-1 | EventBridge + Lambda + SNS | CloudShell (`mark2-3.sh`) |
| [module-4-sqs-scaling](module-4-sqs-scaling/README.md) | SQS Scaling | us-west-2 | EKS(Fargate) + KEDA(SQS) + Karpenter | CloudShell (`mark2-4.sh`) |

각 모듈의 배포·채점·teardown 절차는 해당 모듈 README(런북)를 따른다. 여기서는 절차를 반복하지 않고 모듈 간 공통 사항만 다룬다.

> **대회 당일에는 [DAY-OF.md](../../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로,
> 아래 값 대조표로 종이 과제지를 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.

## 값 대조표 (당일 종이 과제지 대조용)

| 모듈 | 리전 | 준비본 이름·값 | CIDR |
|---|---|---|---|
| module-1-nosql | `ap-northeast-2` (`2a`) | VPC `skills-nosql-vpc` / DocDB 클러스터 `skills-nosql-docdb-cluster`·인스턴스 `skills-nosql-docdb-instance-1`(`db.t3.medium`, 포트 `27017`, 백업 `1`일) / Secret `skills-nosql-docdb-secret` / KMS `alias/skills-nosql-docdb` / EC2 `skills-nosql-client-ec2`(`t3.micro`, 앱 `8080`) | `10.63.0.0/16` |
| module-2-lattice | `ap-northeast-1` (`1a`) | Client VPC `skills-lattice-client-vpc` / Service VPC `skills-lattice-service-vpc` / EC2 `skills-lattice-client-ec2`·`skills-lattice-service-ec2` / SN `skills-lattice-sn` / Service `skills-lattice-order-service` / TG `skills-lattice-order-tg` / Listener `skills-lattice-http-listener`(`80` → `8080`) | client `10.61.0.0/16` · service `10.62.0.0/16` |
| module-3-event-handling | `ap-southeast-1` (`1a`) | VPC `skills-ceh-vpc` / EC2 `skills-ceh-ec2`(`t3.micro`) / 보호 SG `skills-ceh-protected-sg` / SNS `skills-ceh-alert-topic` / Lambda `skills-ceh-remediate-fn`(timeout `30`) / Trail `skills-ceh-cloudtrail` / 룰 `skills-ceh-sg-change-rule` | `10.73.0.0/16` |
| module-4-sqs-scaling | `us-west-2` | 클러스터 `skills-sqs-cluster` / SQS `skills-sqs-queue`(visibility `30`) / ECR `skills-sqs-worker` / 접두 `skills-sqs` | `10.64.0.0/16` |

4모듈 모두 `terraform.tfvars` 가 비어 있고 기본값이 과제지 값이다. **다른 값만 tfvars 에 적어 덮는다.**

⚠ **module-4 `cluster_name` 을 바꾸면 tfvars 로 안 끝난다.** `k8s/10-karpenter-nodepool.yaml` 의 `subnetSelectorTerms`(`karpenter.sh/discovery`)·`securityGroupSelectorTerms`(`aws:eks:cluster-name`) 태그 값과 `eksctl/cluster.yaml` 의 정책 ARN·accessEntry, EC2NodeClass `role` 이 이름을 리터럴로 재조립한다. 놓치면 Karpenter 가 서브넷·SG 를 못 찾아 노드 프로비저닝이 조용히 실패한다.

⚠ **module-2 service SG 에 CIDR 을 절대 추가하지 않는다.** 과제지가 `0.0.0.0/0` 허용 시 미충족을 명시한다.

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
- `.env`(본 PC용 `.env.ps1`, CloudShell 업로드용 `.env`)는 `terraform output` 직후 생성한다. 둘 다 gitignore 대상 — **재부팅·CloudShell 세션 초기화 시(40분동안 비대화형 상태일떄)** 재생성/재업로드.
- module-4는 로컬에 Docker가 없어 이미지 build/push가 CloudShell 필수 경로다. mark 스크립트도 `jq` 의존이라 로컬 대체 실행이 불가 — CloudShell 접속을 0단계에서 먼저 확인한다.
> 트랩·원인은 [NOTES.md](NOTES.md) 함정 참고.

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
