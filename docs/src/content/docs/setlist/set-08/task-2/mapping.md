---
title: 요구사항 ↔ 구현 매핑
description: 8세트 2과제 채점 항목별 구현 위치 (reference)
sidebar:
  order: 4
---

채점 스크립트(`set-08/task-2/mark/mark2-N.sh`) 항목 기준. 배점은 모듈당 7.5점, 항목당 1.5점(모듈 1·2·3) 또는 1.25점(모듈 4).

## 모듈 1 — NoSQL DocumentDB (mark2-1.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 1-1 | 1.5 | Cluster `skills-nosql-docdb-cluster`(암호화+KMS·backup·endpoint) + Instance `skills-nosql-docdb-instance-1`(db.t3.medium) + KMS `alias/skills-nosql-docdb` | `module-1-nosql/terraform/docdb.tf` |
| 1-2 | 1.5 | Secret `skills-nosql-docdb-secret`(username/host/password_set) + EC2 `skills-nosql-client-ec2` running + Public IP | `terraform/secrets.tf` + `ec2.tf` |
| 1-3 | 1.5 | `:8080/health`·`/v1/admin/summary` 200 — counts orders 8/products 6/sessions 3, BSON Date | `terraform/userdata.sh.tftpl`(pip·CA bundle·systemd serve·seed 재시도) |
| 1-4 | 1.5 | `/v1/admin/indexes` 200 — 과제지 3-3 인덱스 8종 + TTL `expireAfterSeconds: 0` | `terraform/index_setup.py.tftpl` |
| 1-5 | 1.5 | 조회 API 4종 200 + 조건 일치 데이터 | 지급 앱 조회 로직 (1-3 적재·1-4 인덱스 전제) |

주의: 지급 앱이 region·secret 이름·DB 이름·port를 상수로 갖는다 — terraform 변수만 바꾸면 앱과 어긋난다. TTL 인덱스는 실제로 동작하므로 dataset의 `sessions.expiresAt`이 채점 시점보다 미래여야 한다(NOTES 함정 절).

## 모듈 2 — VPC Lattice (mark2-2.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 2-1 | 1.5 | Client/Service VPC 존재(`skills-lattice-client-vpc` 10.61.0.0/16 · `skills-lattice-service-vpc` 10.62.0.0/16), 서브넷 구성 | `module-2-lattice/terraform/vpc.tf` |
| 2-2 | 1.5 | Client/Service EC2 running, Client 앱 `/health` 200 | `module-2-lattice/terraform/ec2.tf` (지급 앱 base64 user-data) |
| 2-3 | 1.5 | Service Network `skills-lattice-sn` + Service `skills-lattice-order-service`(dns_entry) + SN-Service association | `module-2-lattice/terraform/lattice.tf` |
| 2-4 | 1.5 | Target Group `skills-lattice-order-tg`(INSTANCE/HTTP:8080) + Listener `skills-lattice-http-listener`(HTTP:80→forward) + Service SG(prefix list 소스만) | `module-2-lattice/terraform/lattice.tf` + `sg.tf` |
| 2-5 | 1.5 | `GET /v1/client/orders?id=1001` → `service.order_id=1001, service.via=vpc-lattice` | `ec2.tf`의 `SERVICE_URL` terraform 참조 주입 → `client_app.py`가 Lattice 경유로 `service_app.py` 호출 |

주의: 2-4의 Service SG는 VPC Lattice Managed Prefix List 소스만 허용해야 하며(과제지 4-3), `0.0.0.0/0`을 열면 그 시점에 명시적으로 미충족 처리된다. 2-3의 SN-VPC association은 Client VPC 하나만 두는 설계라, Service VPC를 검사하는 채점 항목이 있다면 이 매핑을 재확인해야 한다.

## 모듈 3 — Cloud Event Handling (mark2-3.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 3-1 | 1.5 | VPC `skills-ceh-vpc`(10.73.0.0/16) + EC2 `skills-ceh-ec2` running(SG 연결) + SG `skills-ceh-protected-sg` | `module-3-event-handling/terraform/vpc.tf` + `sg.tf` |
| 3-2 | 1.5 | 보호 SG Inbound 규칙 0개 | `sg.tf` — ingress 리소스 미선언 |
| 3-3 | 1.5 | Topic `skills-ceh-alert-topic` + Lambda `skills-ceh-remediate-fn`(python3.12/handler/timeout 30/env 2개) | `sns.tf` + `lambda.tf` |
| 3-4 | 1.5 | Trail `skills-ceh-cloudtrail` IsLogging + Rule `skills-ceh-sg-change-rule`(패턴·target) + Lambda resource policy | `cloudtrail.tf` + `eventbridge.tf` |
| 3-5 | 1.5 | TCP/22 임시 추가 → Lambda 직접 invoke → Inbound 0 복귀 + 로그 그룹 존재 | 지급 Lambda + `lambda.tf` 로그 그룹 선생성 |

주의: 3-5는 EventBridge 실경로가 아니라 Lambda 직접 invoke로 검증하므로 CloudTrail 이벤트 전달 지연은 채점에 영향이 없다. 실경로 동작은 런북 검증 2에서 별도로 확인한다.

## 모듈 4 — SQS Scaling (mark2-4.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 4-1 | 1.25 | `skills-sqs-cluster` + VPC + Fargate Profile `skills-sqs-fp-keda`·`skills-sqs-fp-karpenter` | `module-4-sqs-scaling/eksctl/cluster.yaml` + `terraform/vpc.tf` |
| 4-2 | 1.25 | `skills-sqs-queue` + IRSA ServiceAccount 3개(`keda-operator`/`karpenter`/`sqs-worker-sa`)의 role-arn annotation | `terraform/sqs.tf` + `eksctl/cluster.yaml` `iam.serviceAccounts` |
| 4-3 | 1.25 | `keda`·`karpenter` 네임스페이스에 컨트롤러 Pod 존재(Fargate 배포) | README 4단계 helm install + Fargate Profile 2개 |
| 4-4 | 1.25 | Deployment `sqs-worker`(env 3개) + ScaledObject `sqs-worker-scaledobject`/TriggerAuthentication `sqs-worker-trigger-auth`(min 0/max 6/queueLength 2) | `k8s/20-deployment.yaml` + `k8s/30-keda-scaledobject.yaml` |
| 4-5 | 1.25 | NodePool `skills-sqs-nodepool` + EC2NodeClass `skills-sqs-nodeclass`(label `skills-nodepool=event-worker`, `disruption.consolidationPolicy` 포함) + Worker Pod가 Karpenter 노드에 배치 | `k8s/10-karpenter-nodepool.yaml` + `20-deployment.yaml` nodeSelector |
| 4-6 | 1.25 | 메시지 12건 발송 후 scale-out(pod·노드 증가) 확인 | ScaledObject queueLength 2/max 6 + NodePool 인스턴스 타입(t3.medium/large) |

주의: 4-5는 채점 스크립트 순서상 4-6(부하 유발)보다 먼저 실행된다. `minReplicaCount: 0`이라 큐가 비어 있으면 4-5 시점에 워커 Pod·Karpenter 노드가 0개인 상태가 정상이며, 이는 실패가 아니라 설계된 동작이다. coredns가 Fargate로 강제된 것(`skills-sqs-fp-kube-system` 추가 profile)은 4-1의 명시 검사 대상(profile 2개)에는 없지만 4-3의 컨트롤러 기동 자체를 성립시키는 전제조건이다.
