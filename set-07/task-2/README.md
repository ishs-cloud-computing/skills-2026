# 2026 전국기능경기대회 클라우드컴퓨팅 제2과제 — Small Challenge (set-07)

독립 모듈 4개, 각기 다른 리전. 모듈별 상세 런북은 각 모듈 README 를 따른다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 런북 | 채점 |
|------|------|------|-------------|------|------|
| 1 | NoSQL 예약 시스템 | ap-southeast-1 | DynamoDB(Stream/GSI/PITR), Lambda, EC2 | [module-1-nosql](module-1-nosql/README.md) | `mark/mark1.sh` |
| 2 | CDN A/B 테스팅 | us-east-1 | CloudFront Functions, KVS, OAC, S3 | [module-2-cdn-function](module-2-cdn-function/README.md) | `mark/mark2.sh` |
| 3 | EKS 스케일링 | ap-northeast-2 | SQS, EKS 1.35, KEDA, Karpenter | [module-3-eks-scaling](module-3-eks-scaling/README.md) | `mark/mark3.sh` |
| 4 | 컨테이너 로깅 | ap-northeast-1 | EKS 1.35, OTel Collector, Loki, Grafana, ALB | [module-4-container-logging](module-4-container-logging/README.md) | `mark/mark4.sh` |

## 공통 워크플로

1. `terraform apply` 는 **본 PC** 에서만 한다 (모듈별 `terraform/`).
2. 모듈 3·4 는 bastion(terraform 이 생성, docker/eksctl/helm 설치됨)에서 클러스터 생성·이미지 빌드·kubectl 작업을 한다. bastion 에는 `outputs.json` 만 넘기고 tfstate/`.terraform/` 은 넘기지 않는다.
3. 모듈 3·4 의 `eksctl create cluster` 전 bastion 에서 `aws configure` 로 **선수 IAM 키**를 넣는다 — 클러스터 생성자 = 채점 CloudShell 신원이어야 `kubectl-connect` 가 동작한다.
4. 셀프 채점은 각 모듈 리전의 **CloudShell** 에서 `mark/markN.sh` 로 한다. mark1/2/4 는 `rm -rf ~/.aws` 를 수행하므로 본 PC/bastion 에서 실행하지 않는다.
5. 과제 종료 전 부하를 모두 중지한다 — 모듈 3 은 Pod 1 / Karpenter 노드 1 상태여야 한다.

## 문서

설계 근거·채점 항목 매핑·주의사항은 `docs/src/content/docs/setlist/set-07/task-2/` (Starlight 사이트) 에 있다.

- 제공 파일(`provided/`, `task.md`, `mark.md`, `mark/*.sh`)은 수정하지 않는다.
- 모듈별 사용 파일: `provided/Module1-NoSQL`(terraform 직접 참조), `Module2-CDN-Function`(terraform 직접 참조), `Module3-EKS-Scaling`(bastion 빌드), `Module4-Container-Logging`(app.py 만 사용 — Dockerfile 은 결함으로 자체 작성분 사용).
