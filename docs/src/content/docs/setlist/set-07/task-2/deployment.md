---
title: 설계 근거
description: 7세트 2과제 — 왜 이렇게 구성했는가 (explanation)
sidebar:
  order: 3
---

각 선택의 "왜"만 다룬다. 실행 절차는 [런북](../runbook/), 채점 대조는 [매핑](../mapping/) 참고.

## 모듈 1 — NoSQL

### 왜 자체 VPC인가

과제지 자체는 VPC를 요구하지 않아 default VPC가 최소 구성이지만, 대회 당일 30% 변동으로 "VPC 이름/CIDR 지정"이 추가될 수 있다. data source 기반 default VPC는 변수화할 이름·CIDR이 코드에 없어서 그 변동을 흡수하지 못한다 — retrofit 시 리소스 5개 신규 작성에 서브넷 교체로 인스턴스까지 재생성된다. 자체 VPC(+public 서브넷·IGW·라우팅, 전부 무료)는 리소스 5개를 미리 지불하고 이름·CIDR을 `vpc_name`/`vpc_cidr`/`subnet_cidr` 변수로 열어둔다. default VPC가 삭제된 계정에서도 동작한다는 부수 이득도 있다.

### 왜 GSI를 key_schema 블록으로 선언하나

AWS provider 6.x에서 `global_secondary_index`의 `hash_key`/`range_key` 인자는 deprecated다(6.56 문서 기준). `key_schema` 블록이 현행 문법이며, 결과 리소스는 동일하다.

### 왜 GSI 키가 user_id/reserved_at인가 (sparse의 핵심)

채점 1-6-A는 취소 후 `/my-bookings` 조회가 0건이 되는지 본다. DynamoDB GSI는 키 속성이 없는 아이템을 인덱스에 넣지 않는다(sparse). 지급 `app.py`가 취소 시 `REMOVE user_id, reserved_at`을 수행하므로, GSI 키를 정확히 이 두 속성으로 잡아야 취소된 예약이 인덱스에서 자동 제외된다. 인프라 쪽에 sparse "설정"은 없다 — 키 선택이 곧 설정이다.

### 왜 handler가 lambda.handler인가

지급 파일 `lambda.py`는 무수정 사용 조건이다. 파일명이 python 예약어 `lambda`와 같지만, Lambda 런타임은 모듈을 importlib로 로드하므로 `import lambda` 구문 제약과 무관하게 동작한다. zip 내부 파일명을 개명하는 우회(archive_file `source` 블록)는 불필요해서 기각했다.

### 왜 app.py를 user-data로 배포하나

module-1은 Dockerfile이 지급되지 않았다 — EC2 직접 실행이 전제다. app.py + requirements.txt는 base64로 ~7KB라 user-data 16KB 한도 안에 넉넉히 들어간다. S3 경유는 버킷·IAM·순서 의존만 늘린다. systemd `Restart=always`로 pip 설치가 끝나기 전 기동 실패를 자동 복구한다.

### 왜 ESM이 정확히 1개여야 하나

채점 1-3-A는 `list-event-source-mappings` 출력 전체를 기대값과 정확 일치로 비교한다. 트리거가 2개면 출력 줄이 늘어 실패한다. 같은 이유로 GSI도 1개만 둔다(1-2-A).

### IAM 범위

유의사항 11이 `Principal:"*"`·`Action:"*"`을 금지한다. EC2 롤은 앱이 실제 호출하는 `UpdateItem`(예약/취소)과 `Query`(테이블+GSI)만, Lambda 롤은 스트림 읽기 3종 + audit `PutItem` + 로그 쓰기만 갖는다.
