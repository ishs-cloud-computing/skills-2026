---
title: "리스크 순위"
sidebar:
  order: 9
---

| 순위 | 항목 | 리스크 | 대응 |
|---|---|---|---|
| 1 | 커스텀 노드명 + `provider-id` / CCM 상호작용 | 노드가 NotReady에 머물 수 있음. 문서로 완전 확정 안 되는 지점 | 사전에 클러스터 1회 생성해 실측 |
| 2 | zstd 이미지 노드 구동 | 로컬 검증 불가 | 사전 배포 리허설 |
| 3 | SGP strict + TargetGroupBinding 조합 | 타깃이 unhealthy로 남을 수 있음 | ALB SG→Pod SG 8080 규칙 실측 |
| 4 | eksctl managed nodegroup의 `bottlerocket.settings` 반영 | 과거 user-data 미반영 버그 이력 | 생성 후 `kubectl get nodes` 즉시 확인, 실패 시 self-managed `nodeGroups`로 fallback |
| 5 | CLOUDFRONT scope Web ACL의 us-east-1 provider 설정 실수 | apply 시 리전 오류로 실패 | provider alias 명시, plan 단계에서 확인 |
