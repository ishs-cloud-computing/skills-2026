---
title: 주의 · 알려진 한계
description: 30% 변동 대응, 채점 스크립트 오타, 실발화 불가 알람 등 함정과 리소스 정리
sidebar:
  order: 5
---

## 주의 / 알려진 한계

- **이름 접두어 변경(30% 변동) 대응**: terraform 은 `name_prefix` 변수(기본 `wsc2026`)로 일괄 변경
  가능. k8s/eksctl 은 라벨 키 `wsc2026/node` 를 포함해 접두어가 파일 전반에 박혀 있어, cluster.yaml 과
  manifest 를 `grep -rl wsc2026 eksctl k8s app | xargs sed -i 's/wsc2026/<새접두어>/g'` 로 함께
  치환해야 일관된다. 네트워크(`-skills-*`)·클러스터·테이블·ECR·Lambda·버킷 이름은 별도 변수라
  tfvars 에서 개별 변경 대상이다.
- **mark 5-5 항목 오타(발견·수정 완료)**: 채점지 5-5 가 클러스터를 `wsi2026-xxxxx` 형식으로 조회하는
  오류가 있어 저장소 `mark.sh` 를 올바른 `wsc2026-eks-cluster` 로 수정했다. 구현은 실제 클러스터에
  정상 구성돼 있다(`aws eks list-pod-identity-associations --cluster-name wsc2026-eks-cluster --namespace wsc2026` 로 확인).
  관련 사항은 마이스터넷에 질의한 상태다.
- **11-4 HighLatency 실발화 불가**: 제공 book 바이너리에 `/delay` 엔드포인트가 없다(로컬 실측 — 404, µs 응답).
  채점 스크립트의 latency-gen 으로는 평균 응답 3초 초과를 만들 수 없다. 룰은 사양(3s/1m)대로 구현했고,
  대회 당일 바이너리에 /delay 가 있으면 그대로 동작한다. 나머지 알람(PodHighCPU/PodHighMemory/PodNotReady/
  HighErrorRate/PodCrashLooping)은 채점 스크립트의 부하 파드로 발화된다.
- **KMS root/kms:* 금지(유의 10)**: 5키 모두 배포자 신원(`aws_iam_session_context`) + 서비스별 최소 statement.
  **대회 지급 계정은 root 이므로 step 0 에서 IAM 사용자(wsc2026-admin)를 만들고,
  terraform/eksctl/docker push/kubectl/채점을 전부 그 신원으로** 실행한다.
  root 로는 KMS 사용은 물론 alias 생성·CMK 테이블/객체 생성도 전부 거부된다(키 정책이 유일한 통제).
  다른 관리자를 추가하려면 `kms_extra_admin_arns` 변수 사용. root 자격증명은 plan 단계에서 차단된다.
- **VPC CloudShell 은 비영속**: 홈 디렉토리가 세션 종료 시 삭제되고 업로드 UI 도 없다.
  도구/파일/kubeconfig 는 step 4 셋업 블록 하나로 복구한다(재접속 시 통째로 재실행, 약 1–2분).
- **HTTP 메트릭은 로그 기반**: 앱이 /metrics 를 노출하지 않아 fluent-bit `log_to_metrics` 필터가
  액세스 로그에서 requests/errors counter 와 duration histogram 을 생성한다(`:2021/metrics`).
  배포 후 step 8 에서 **메트릭 실명을 확인**하고 `prometheus-rules.yaml`/`dashboard.json` 의
  `log_metric_counter_wsc2026_*` 이름과 다르면 맞춘다. aws-for-fluent-bit 이미지에 log_to_metrics 가
  없으면 upstream `fluent/fluent-bit` 최신 안정 태그로 교체(fallback).
- **ALB SG 단독 부착**: ingress 의 `security-groups` 어노테이션에 `wsc2026-app-alb-sg` 만 지정하고
  `manage-backend-security-group-rules` 는 쓰지 않는다(mark 8-1 이 SG 이름 단독 출력 요구).
  ALB→Pod 8080 은 Terraform `wsc2026-eks-shared-node-sg`(노드 attachIDs)가 사전 허용한다.
- **CoreDNS 도메인**: kubelet clusterDomain(eksctl `overrideBootstrapCommand`의 nodeadm NodeConfig)과
  CoreDNS Corefile 패치가 **모두** 적용돼야 파드 DNS 가 정상 동작한다. coredns addon 업데이트 시
  Corefile 이 초기화될 수 있으므로 업데이트 금지, 했다면 재적용 후 mark 4-1 grep 재확인.
- **CloudFront /booking**: 앱은 POST `/v1/book` 만 제공 — CloudFront Function(viewer-request)이
  `/booking` → `/v1/book` 으로 rewrite 한다. ALB 는 경로 rewrite 가 불가하다.
- **Lambda 환경변수**: `TABLE_NAME` 값 자체가 KMS 암호문(`aws_kms_ciphertext`)이고 코드가 런타임에
  복호화한다(전송 중 암호화). `kms_key_arn` 은 저장 시 암호화. 두 가지 모두 wsc2026-function-kms.
- **이미지 풀**: app 서브넷에 NAT 가 있어 공개 레지스트리(LBC/kps/fluent-bit)는 직접 pull.
  eks/eks-auth Interface Endpoint 는 만들지 않는다(PHZ 가 Pod Identity 를 깨는 함정 — `endpoints.tf` 주석).

## 리소스 정리 유의사항

- DynamoDB 삭제 방지 해제(`deletion_protection_enabled=false` 로 apply) 후 destroy.
- S3 는 `force_destroy` 미설정 — 객체(정적 파일·릴레이) 비운 후 destroy.
- CloudFront 비활성→삭제에 시간이 걸린다(2차 apply 리소스부터 역순 destroy 권장).
