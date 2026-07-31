---
title: 요구사항 ↔ 구현 매핑
description: 7세트 2과제 채점 항목별 구현 위치 (reference)
sidebar:
  order: 4
---

채점 스크립트(`set-07/task-2/mark/markN.sh`) 항목 기준. 배점은 모듈당 7.5점.

## 모듈 1 — NoSQL (mark1.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 1-1-A | 1.5 | reservation 테이블: PK train_id(S)/SK seat_id(S), Streams NEW_AND_OLD_IMAGES, PAY_PER_REQUEST, PITR ENABLED | `terraform/dynamodb.tf` `aws_dynamodb_table.reservation` |
| 1-2-A | 1.0 | GSI `gsi-user-reservations`(HASH user_id/RANGE reserved_at, ALL) 정확히 1개 + audit 테이블 PK event_id(S) | `terraform/dynamodb.tf` GSI 블록 + `aws_dynamodb_table.audit` |
| 1-3-A | 1.0 | Lambda python3.13/timeout 30 + reservation 스트림 ESM 1개 State=Enabled | `terraform/lambda.tf` |
| 1-4-A | 1.0 | Name=`bigbae-nosql-app-ec2` running 1대, Public IP, :8080/healthcheck 200 | `terraform/ec2.tf` + `userdata.sh.tftpl` |
| 1-5-A | 1.5 | reserve→reserve→cancel→cancel = 200/409/409/200 (본문 정확 일치) | 지급 `provided/module-1/app.py` 무수정 + env 3개(`userdata.sh.tftpl`) |
| 1-6-A | 1.5 | GSI 즉시 조회 1건 → 취소 후 0건(sparse) → audit 1→2건(30초 내) | GSI 키 선택(`dynamodb.tf`) + Lambda IAM/ESM(`lambda.tf`) |

주의: 1-2-A·1-3-A는 출력 **정확 일치**라 GSI·ESM을 추가로 만들면 실패한다. 1-5-A 응답 본문의 키 순서는 Flask `jsonify` 기본 정렬에 의존하므로 지급 `app.py`를 수정하지 않는 것이 곧 충족 조건이다.

## 모듈 2 — CDN Function (mark2.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 2-1-A | 1.0 | 버킷 `skillsphone-landing-ab-<ACCOUNT_ID>`, 오브젝트 `version-a/index.html`·`version-b/index.html`, PAB 4개 true, 정책 Statement[0] = Service principal + `AWS:SourceArn` | `terraform/s3.tf` |
| 2-2-A | 1.0 | KVS `skillsphone-cdn-ab-config` 키 정확히 3개(weight 0.3, version_a/b 경로), 함수 2개 LIVE(DEPLOYED)·cloudfront-js-2.0, req-fn에 KVS 연결 | `terraform/functions.tf` |
| 2-3-A | 1.0 | 캐시 정책 whitelist `x-sp-ab`·TTL 0/300/3600, redirect-to-https, OAC 연결, default behavior에 함수 2개 | `terraform/cloudfront.tf` |
| 2-4-A | 1.5 | 쿠키 a/b 강제 시 해당 본문 + **Set-Cookie 없음**, HTTP→HTTPS 30x | `cloudfront/req-fn.js`(쿠키 분기) + `res-fn.js`(헤더 게이트) |
| 2-5-A | 1.5 | 첫 방문 배정(a/b) + `Path=/; Max-Age=86400` Set-Cookie + 본문 일치, 재방문 유지·Set-Cookie 없음 | `cloudfront/req-fn.js` + `res-fn.js` |
| 2-6-A | 1.5 | weight 1.0→`/version-b/index.html`, 0.0→`/version-a/index.html` (test-function, KVS 실시간 반영) | `cloudfront/req-fn.js`(매 실행 KVS read, 하드코딩 없음) |

주의: 2-2-A는 키 목록 **정확 일치**라 KVS에 여분 키를 넣으면 실패한다(`keys_exclusive`가 구조적으로 방지). 2-3-A는 distribution을 **Comment 값**(`skillsphone-cdn-ab-distribution`)으로 식별하므로 comment를 비우면 0점이다. 2-6-A는 채점 스크립트가 weight를 직접 변경 후 0.3으로 복원한다 — 채점 직후 plan에서 KVS drift가 보여도 복원 완료면 무시한다.

## 모듈 3 — EKS Scaling (mark3.sh)

| 항목 | 배점 | 검사 내용 | 구현 위치 |
|------|------|-----------|-----------|
| 3-1-A | 0.35 | 큐 URL `.../skm-order-queue` | `terraform/sqs.tf` |
| 3-2-A | 0.75 | 클러스터 `skm-eks-cluster 1.35 ACTIVE`, NG `t3.medium 1 1 1`, 인스턴스 `tag:Name=skm-cluster-addon-ng-node` | `eksctl/cluster.yaml` (Name 태그는 `instanceName` 필드) |
| 3-3-A | 1.0 | 앱 Pod의 노드에 `karpenter.sh/nodepool=skm-app-nodepool` 라벨, replicas 1·8080·500m/512Mi, env 3개 정렬 덤프 정확 일치 | `k8s/20-deployment.yaml` (nodeSelector+toleration) |
| 3-4-A | 1.2 | `keda` ns에 keda-operator Pod, ScaledObject `1 5 aws-sqs-queue 5` | helm KEDA 2.20.1 + `k8s/30-keda-scaledobject.yaml` |
| 3-5-A | 1.2 | kube-system에 karpenter Pod, NodePool `WhenEmptyOrUnderutilized 60s`·`t3.medium,t3.small`·taints ≥1, EC2NodeClass 존재 | helm Karpenter 1.14.0 + `k8s/10-karpenter-nodepool.yaml` |
| 3-6-A/B | 1.5 | 메시지 100건 주입 → 2분 내 Ready Pod ≥5, Karpenter 노드 ≥2 | KEDA queueLength 5 + 용량 계산(500m×5 > 노드 1대 allocatable) |
| 3-7-A/B | 1.5 | purge → 150초 내 Pod 1·노드 1 | ScaledObject scaleDown behavior 오버라이드 + consolidateAfter 60s |

주의: 3-3-A는 env 전체를 sort 덤프해 **정확 일치**로 비교하므로 env를 하나라도 추가하면 실패한다. 3-2-A의 노드 Name 태그는 MNG `tags`가 아니라 eksctl `instanceName`으로만 인스턴스에 붙는다. 3-4·3-5·3-6 중 하나라도 틀리면 3-7은 채점되지 않는다. 채점 전 상시 상태는 Pod 1개·Karpenter 노드 1대·빈 큐다.
