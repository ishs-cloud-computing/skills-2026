---
title: "함정·주의사항"
sidebar:
  order: 7
---

1. **서브넷 추가 금지**: 1-1은 VPC 내 전 서브넷을 나열해 정확 비교한다(3번째 서브넷을 만들면 즉시 오답). 단 Gateway Endpoint는 서브넷이 아니라 라우트만 추가하고 그 라우트는 1-2 쿼리에서 자동 제외되므로(§0-2) 안전하다.
2. **NAT 0개**: 계정 전체 `describe-nat-gateways` 개수가 0이어야 한다. 임시로 만든 NAT를 남기면 실패.
3. **ECR 이미지 3MB**: 기본 gzip으로 push하면 3.32MiB로 초과. zstd 압축 push가 유일한 통과 경로이며, 태그는 `latest`.
4. **pull-through cache rule(`ecr-public`)**: 4-5 채점이 이 URL로 nginx를 pull 한다. 룰 누락 = 1.5점 손실.
5. **DynamoDB Deny 정책이 자기 발등을 찍는다**: 정책 활성 상태에서는 관리자도 아이템 삭제 불가 → "데이터 0개" 요구를 먼저 처리하는 순서를 지킨다.
6. **WAF method 규칙 스코프**: `/v1/book` 한정. 전역 적용 시 Grafana·Lambda 조회가 모두 차단된다.
7. **8-1의 Hit 조건**: `/`가 CloudFront Function으로 `/index.html`이 되어 캐시 키가 합쳐져야 세 번째 요청이 Hit. `default_root_object`만으로는 불가.
8. **Fluent Bit는 파싱이 본체**: 평문 액세스 로그를 JSON으로 구조화하지 않으면 채점의 `jq .remote_addr`가 실패한다.
9. **book Pod AZ 분산**: 한쪽 AZ에만 있으면 10-1의 로그 스트림이 1개만 생겨 감점.
10. **EKS 엔드포인트 public 활성**: private-only로 만들면 채점 CloudShell의 kubectl이 동작하지 않는다(4-1 `True True`도 불일치).
11. **채점은 CloudShell**: 로컬에서만 되는 구성(포트포워딩 등)에 의존하지 않는다.
12. **CloudFront 반영 지연**: 배포·무효화에 최대 3분 이상. 경기 후반 수정 시간을 계산에 넣는다.
13. **`ami:` 지정 금지**: amiType이 `CUSTOM`이 되어 4-2 문자열 비교가 깨진다.
14. **t3.medium에는 SGP가 동작하지 않는다**: t 패밀리는 trunk ENI 미지원. app(m5.large) 노드에만 적용.
15. **book Pod에 probe를 달지 않는다**: probe를 살리려면 노드 SG를 8080에 열어야 하고, 그 순간 4-5가 통과된다(=감점).
16. **zstd 이미지는 로컬 `docker run` 불가**: 구동 검증은 클러스터에서만. 사전 리허설 필수.
17. **WAF 정규식 앵커 누락**: 부분 매칭이라 `홍길동`의 URL 인코딩 안 `B8`에 매칭되어 통과해버린다.
18. **WAF `client_id` 존재 검사 누락**: `NOT(regex)` 단독이면 파라미터 없는 8-3 요청까지 403이 된다.
19. **`AllViewerExceptHostHeader` 누락**: 쿼리스트링이 오리진에 안 가서 WAF가 `client_id`를 못 본다 → 9-2 전멸.
20. **Grafana TG 이름은 Ingress로 못 만든다**: LBC가 이름을 강제 생성. Terraform TG + TargetGroupBinding 필수.
21. **Grafana `securityContext` 472 변경 금지**: IRSA 토큰을 못 읽고 조용히 노드 role로 폴백한다.
22. **PTC 첫 pull 워밍업**: 노드에 인터넷이 없으므로 인터넷 있는 CloudShell/로컬에서 미리 pull 해 캐시를 채운다. 노드 role에 `ecr:BatchImportUpstreamImage`, `ecr:CreateRepository` 필요.
23. **Lambda는 ALB 타깃그룹이 아니다**: task.md가 Target Group 이름을 book/grafana 2개만 명시한다. Lambda는 Function URL + CloudFront OAC로 직접 연결한다(§0-1).
24. **WAF는 CLOUDFRONT scope, us-east-1**: REGIONAL로 만들어 ALB에 붙이면 Lambda(`/reservation`) 요청은 검사하지 못한다. 반드시 CloudFront 배포에 `web_acl_id`로 직접 연결.
25. **DynamoDB Gateway Endpoint 필수**: DynamoDB는 Interface Endpoint 자체가 없다(Gateway 전용). rtb-a/b에 연결해도 1-2는 깨지지 않는다(§0-2, jmespath 실측 확인).
26. **Pod SG egress는 DynamoDB를 prefix-list로 열어야 한다**: Gateway Endpoint는 ENI가 없어 "endpoint SG" 참조로는 안 열린다.
