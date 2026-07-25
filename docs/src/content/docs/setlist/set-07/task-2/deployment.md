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

## 모듈 2 — CDN Function

### 왜 CloudFront Functions + KeyValueStore인가

핵심 요구는 "노출 비율 변경이 코드 재배포 없이 즉시 반영"이다. 비율을 함수 코드에 상수로 넣으면 변경 = 재배포라 요구를 정면으로 어긴다. KVS는 함수 코드와 분리된 엣지 설정 저장소로, `put-key` 한 번이면 발행 없이 전 엣지에 전파된다 — 채점 2-6이 정확히 이 동작(weight 1.0/0.0 변경 → test-function 즉시 반영)을 검사한다. Lambda@Edge는 KVS를 못 쓰고(CF Functions 전용) 배포 전파도 분 단위라 기각. KVS를 쓰려면 런타임이 `cloudfront-js-2.0`이어야 하는데, 이는 과제지 요구이기도 하다.

### 왜 Set-Cookie를 viewer-response에서 assigned 헤더로 게이트하나

배정 유지(sticky)의 정합성은 "첫 방문에만 쿠키 발급"에 달려 있다. viewer-request 함수는 신규 배정일 때만 요청 헤더 `x-sp-ab-assigned`를 세우고, viewer-response 함수는 이 헤더가 있을 때만 `Set-Cookie`를 붙인다. 이렇게 하면 재방문(쿠키 보유) 응답에는 Set-Cookie가 절대 없다 — 채점 2-4가 이를 정확 검사한다. viewer-response는 캐시 **뒤**에서 실행되므로 Set-Cookie가 캐시에 저장돼 다른 방문자에게 새는 일도 구조적으로 없다. 대안인 "response에서 request.cookies 부재로 판단"은 배정된 버전(a/b)을 알 방법이 없어 URI 재파싱이 필요해 기각. Set-Cookie 자체는 `response.headers`가 아니라 `response.cookies` 객체로만 설정된다(CloudFront Functions 이벤트 구조).

### 왜 캐시 키에 x-sp-ab 쿠키인가

버전 분리는 사실 viewer-request의 URI 재작성(캐시 조회 전에 실행)만으로도 일어난다 — 캐시 키에 URI가 포함되기 때문이다. 그럼에도 쿠키를 whitelist로 캐시 키에 넣는 것은 과제지 명시 요구이자 채점 2-3 검사 항목이고, URI 재작성 로직이 바뀌어도 A/B 캐시가 섞이지 않게 하는 방어선이다. AWS Managed Policy 금지 조건 때문에 TTL 0/300/3600의 커스텀 캐시 정책과 커스텀 Security Header 정책을 만든다.

### 왜 KVS 키를 keys_exclusive 단일 리소스로 관리하나

채점 2-2는 `list-keys` 출력을 기대값과 정확 일치로 비교한다 — 키가 3개를 초과하면 실점. `aws_cloudfrontkeyvaluestore_keys_exclusive`는 선언 안 된 키를 제거해 "정확히 3개"를 구조적으로 보장하고, 키별 개별 리소스 대비 KVS API 호출도 적다. 대가는 이 리소스가 키 전체의 단독 소유자가 된다는 것인데, 채점 2-6의 out-of-band weight 변경은 스크립트가 스스로 0.3으로 복원하므로 충돌하지 않는다.

### 왜 "Pay-as-you-go 타입"인데 아무 설정이 없나

CloudFront의 flat-rate 요금 플랜(2025-11 출시)은 콘솔 전용 opt-in 구독이고, Terraform·API·CloudFormation에는 플랜 인자 자체가 없다. 즉 Terraform으로 만든 distribution은 구조적으로 pay-as-you-go다. `price_class`는 엣지 로케이션 범위 설정으로 과금 모델과 무관하므로 건드리지 않는다. 부수적으로, 플랜 구독 distribution은 삭제 불가·함수/KVS 공유 불가 제약이 있어 채점용 임시 스택과도 상성이 나쁘다.

### 왜 S3 접근이 OAC인가

과제지가 "CloudFront만 접근 + OAC"를 명시한다. 버킷은 Public Access 전면 차단이고, 버킷 정책은 `cloudfront.amazonaws.com` service principal에 `AWS:SourceArn`을 이 distribution ARN으로 조건 건 단일 statement다 — 채점 2-1이 `Statement[0]` 하나만 검사하므로 statement를 늘리지 않는다. 레거시 OAI는 deprecated라 기각.
