---
title: 설계 근거
description: public 엔드포인트, TargetGroupBinding, raw OTel manifest 등 설계 결정의 이유
sidebar:
  order: 3
---

## 클러스터 엔드포인트를 public+private 로 연 이유 (모듈 3·4)

채점 스크립트가 **CloudShell** 에서 `kubectl-connect`(= update-kubeconfig 후 kubectl)로 접속한다.
private-only 클러스터(set-05 방식)면 채점 셸이 API 서버에 닿지 못한다. public 을 열되 private 도
함께 켜서 노드/bastion 통신은 VPC 내부로 유지한다. bastion(public 서브넷)은 private IP 로 해석된
API 에 접근해야 하므로 `vpc.extraCIDRs` 로 public 서브넷 CIDR 를 cluster SG 443 에 허용한다.

같은 이유로 **클러스터 생성 전 bastion 에서 `aws configure` 로 선수 IAM 키를 넣는다**.
EKS 는 생성자 신원에 자동 admin 권한을 주므로, 생성자 = CloudShell 신원이면 별도 access entry 가 필요 없다.

## ALB 를 terraform + TargetGroupBinding 으로 만든 이유 (모듈 4)

채점 4-2 가 `describe-load-balancers --names o11y-app-alb`, `describe-target-groups --names o11y-app-tg`
처럼 **이름으로 정확 조회**한다. LBC Ingress 는 ALB/TG 이름을 지정할 수 없다(자동 생성 이름).
그래서 ALB·리스너·TG 는 terraform 으로 이름 그대로 만들고, Pod IP 등록만 LBC 의
TargetGroupBinding CRD 에 맡긴다. set-07/task-1 과 같은 패턴이다.

## OTel Collector 를 helm 이 아니라 raw manifest 로 배포한 이유 (모듈 4)

채점 4-3 이 `kubectl get ds o11y-otel` 로 DaemonSet 이름을 정확 검사한다. 공식
opentelemetry-collector 차트는 이름에 `-agent`/`-collector` 접미사를 붙여 이 이름을 만들 수 없다.
DaemonSet 1개 + ConfigMap + RBAC 뿐이라 raw manifest 3개가 차트 값 조정보다 짧고 확실하다.

filelog 의 `container` operator 는 CRI 로그 포맷을 분해하고 파일 경로에서
`k8s.namespace.name`/`k8s.pod.name`/`k8s.pod.uid` 를 리소스 속성으로 추출한다. 본문은 앱이 찍은
JSON 한 줄 그대로 남는다 → Loki 에서 `| json | level="ERROR"` 가 동작한다.

## Loki OTLP 수신과 k8s_namespace_name 라벨 (모듈 4)

채점 4-5 LogQL 이 `{k8s_namespace_name="o11y"}` 를 조회한다. Loki 3.x 는
`limits_config.allow_structured_metadata: true` 일 때 `/otlp` 수신을 활성화하고, 기본 OTLP 설정이
`k8s.namespace.name` 등 잘 알려진 리소스 속성을 인덱스 라벨로 승격한다(점 → 밑줄 변환).
별도 라벨 매핑 설정 없이 기본값으로 충족된다.

## 모듈 4 Dockerfile 을 자체 작성한 이유

제공 Dockerfile 은 `flask` 를 설치하지 않는다(requirements.txt 도 없음) — 그대로 빌드하면
컨테이너가 ImportError 로 기동하지 못한다. 제공 파일은 수정 금지이므로 `app/Dockerfile` 을 따로
작성하고, 빌드 시 제공 `app.py` 를 빌드 컨텍스트로 복사한다. 모듈 3 의 제공 Dockerfile 은 정상이라 그대로 쓴다.

## 스케일 인 타이밍 (모듈 3)

채점 3-7 은 purge 후 최대 2.5분 안에 Pod 1 / 노드 1 을 요구한다. 기본값으로는 실패한다:

- HPA scaleDown stabilization 기본 300초 → ScaledObject `advanced` 로 **30초**로 단축.
- Karpenter consolidation 은 과제지 요구대로 `WhenEmptyOrUnderutilized` + `consolidateAfter: 60s`.

합산: 큐 감지(≤10s) + 안정화 30s + Pod 종료 + 노드 비움 감지 60s ≈ 2분 내 수렴.

Pod 요청 500m × 5 는 t3.medium(allocatable ≈1.9 vCPU) 1대에 들어가지 않아 스케일아웃 시
Karpenter 가 2대째 노드를 프로비저닝한다 — 채점 3-6 의 "노드 ≥2" 는 리소스 계산으로 보장된다.

## 채점이 확인하는 형태 그대로 만든 것들

- 모듈 1 GSI 키를 `user_id`/`reserved_at` 로 두는 것은 제공 `app.py` 의 cancel 이 이 두 속성을
  REMOVE 하는 것과 한 쌍이다 — 이것이 과제가 요구하는 sparse index 구현이다.
- 모듈 2 버킷 정책은 Statement 1개만 둔다(채점이 `Statement[0]` 를 검사).
- 모듈 2 요청 함수는 weight 를 매 호출 KVS 에서 읽는다(채점 2-6 이 put-key 즉시 반영을 검사).
- 모듈 3 deployment env 는 리터럴 3개만 둔다(채점이 `name=value` 문자열로 비교, valueFrom 불가).
- 모듈 3 addon NG 는 `instanceName` 으로 노드 Name 태그를 지정한다 — `tags.Name` 은 eksctl 의
  LT 기본 Name 과 중복되어 무시된다(set-07/task-1 에서 확인된 동작).
