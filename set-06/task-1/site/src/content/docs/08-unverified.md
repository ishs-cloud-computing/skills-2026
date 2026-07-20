---
title: "미확정 항목"
sidebar:
  order: 8
---

| 항목 | 검증 방법 |
|---|---|
| WAF 커스텀 응답 본문 후행 개행 | `curl -s -o /dev/null -w '%{size_download}\n' $CF/v1/book` → 18 / `?client_id=123abc` → 13 |
| CLOUDFRONT scope Web ACL이 Lambda Function URL 오리진 앞에서도 정상 evaluate되는지 | `?client_id=123abc`로 `/reservation` 호출 시 403 확인 |
| 커스텀 노드명 + `provider-id` / CCM | `kubectl get nodes` 가 Ready + 이름 포맷 일치 |
| zstd 이미지 노드 구동 | Pod Running 도달 |
| Grafana sidecar 대시보드 JSON 래핑 형태 | UI에 `WSI Dashboard` 노출 확인 |
