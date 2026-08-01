---
title: 요구사항 ↔ 구현 매핑
description: 8세트 2과제 채점 항목별 구현 위치 (reference)
sidebar:
  order: 4
---

채점 스크립트(`set-08/task-2/mark/mark2-N.sh`) 항목 기준. 배점은 모듈당 7.5점, 항목당 1.5점(모듈 2) 또는 1.25점(모듈 4). 이번 문서는 구현이 끝난 **모듈 2·4**만 다룬다.

## 모듈 2 — VPC Lattice (mark2-2.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 2-1 | 1.5 | Client/Service VPC 존재(`skills-lattice-client-vpc` 10.61.0.0/16 · `skills-lattice-service-vpc` 10.62.0.0/16), 서브넷 구성 | `module-2-lattice/terraform/vpc.tf` |
| 2-2 | 1.5 | Client/Service EC2 running, Client 앱 `/health` 200 | `module-2-lattice/terraform/ec2.tf` (지급 앱 base64 user-data) |
| 2-3 | 1.5 | Service Network `skills-lattice-sn` + Service `skills-lattice-order-service`(dns_entry) + SN-Service association | `module-2-lattice/terraform/lattice.tf` |
| 2-4 | 1.5 | Target Group `skills-lattice-order-tg`(INSTANCE/HTTP:8080) + Listener `skills-lattice-http-listener`(HTTP:80→forward) + Service SG(prefix list 소스만) | `module-2-lattice/terraform/lattice.tf` + `sg.tf` |
| 2-5 | 1.5 | `GET /v1/client/orders?id=1001` → `service.order_id=1001, service.via=vpc-lattice` | `ec2.tf`의 `SERVICE_URL` terraform 참조 주입 → `client_app.py`가 Lattice 경유로 `service_app.py` 호출 |

주의: 2-4의 Service SG는 VPC Lattice Managed Prefix List 소스만 허용해야 하며(과제지 4-3), `0.0.0.0/0`을 열면 그 시점에 명시적으로 미충족 처리된다. 2-3의 SN-VPC association은 Client VPC 하나만 두는 설계라, Service VPC를 검사하는 채점 항목이 있다면 이 매핑을 재확인해야 한다.

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
