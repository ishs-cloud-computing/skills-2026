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
