---
title: 주의 · 알려진 한계
description: 30% 변동 대응, 채점 타이밍, 제공 파일 결함 등 함정
sidebar:
  order: 5
---

## 주의 / 알려진 한계

- **이름 변경(30% 변동) 대응**: terraform 리소스 이름은 각 모듈 `terraform.tfvars` 로 바꾼다.
  eksctl/k8s YAML 에 박힌 채점 대상 리터럴(`skm-`, `o11y-` 접두어, `order-processor` 등)은
  `grep -rl 'skm-' eksctl k8s | xargs sed -i 's/skm-/<새접두어>-/g'` 식으로 일괄 치환한다.
  모듈 2 의 함수 코드(`func/*.js`)에는 쿠키 이름 `x-sp-ab` 과 KVS 키 이름이 박혀 있다 — 쿠키/키
  이름이 바뀌면 JS 도 함께 수정해야 한다.
- **제공 Dockerfile 결함(모듈 4)**: flask 미설치 + requirements.txt 없음. 자체 `app/Dockerfile` 로
  빌드한다. 대회 당일 제공본이 수정되어 있으면 제공본을 우선 사용한다(작업규칙 2 예외).
- **mark1/2/4 는 `rm -rf ~/.aws` 수행**: CloudShell 에서 실행한다. CloudShell 자격증명은 콘솔
  세션 기반이라 삭제와 무관하다. mark3 은 이 삭제를 하지 않아 클러스터 접근이 유지된다.
- **KVS weight drift(모듈 2)**: 채점 2-6 이 weight 를 바꿨다가 0.3 으로 복원한다. 채점 후
  `terraform plan` 에 drift 가 보이면 복원 실패 → 재-apply. `keys_exclusive` 리소스라 선언값으로 수렴한다.
- **KEDA 차트 tolerations 스키마(작업규칙 7)**: addon 노드가 taint 되어 있어 KEDA Pod 에
  toleration 이 필요하다. 차트 2.20.1 은 최상위 `tolerations` 값을 쓰지만, 버전이 바뀌면
  `helm show values` 로 키를 재확인한다. Pending Pod 가 남으면 이것부터 의심한다.
- **addon 노드 1대 용량(모듈 3)**: t3.medium 1대에 coredns 2 + KEDA 3 + Karpenter 1 이 올라간다.
  Karpenter requests 를 0.5 vCPU/512Mi 로 낮춰 설치한다(런북 반영). 그래도 Pending 이면
  KEDA metricServer/webhooks requests 를 추가로 낮춘다.
- **스케일인 창 2.5분(모듈 3)**: ScaledObject `stabilizationWindowSeconds: 30` 과 NodePool
  `consolidateAfter: 60s` 가 한 쌍이다. 어느 쪽도 늘리지 않는다.
- **OTel 재시작 시 로그 유실/중복(모듈 4)**: filelog 는 `start_at: end` 이고 체크포인트 저장소를
  두지 않았다. 채점은 채점 시점에 새로 생성되는 로그만 보므로 문제 없지만, 콜렉터 재시작 직전
  로그는 유실될 수 있다. 필요해지면 file_storage extension 으로 체크포인트를 추가한다.
- **Grafana 패널 데이터(모듈 4)**: No Data 패널이 하나라도 있으면 4-6 오답. 채점 전
  `/log?level=info|warn|error` 를 각각 호출해 3개 레벨 데이터를 만들어 둔다.
- **모듈 1 채점 재시도**: 1-5/1-6 은 새 `train_id` 로 실행되므로 재시도에 안전하다. 감사 테이블
  적재는 Stream → Lambda 경유로 수 초 걸린다(채점이 sleep 30 을 포함).
- **CloudFront 전파 지연(모듈 2)**: apply 완료 후에도 함수/KVS 변경 전파에 수십 초가 걸릴 수 있다.
  2-6 채점 스크립트 자체가 60회 재시도를 포함한다.
