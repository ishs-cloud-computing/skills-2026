# app — 자체 IAM 인증 producer (placeholder)

제공 바이너리(`../../provided/module4/app`)는 SASL/IAM signer 가 없어 9094 비인증 TLS 로만
접속한다(`../BINARY-ANALYSIS.md`). 과제지 "MSK 는 IAM 인증을 통해서만 접근" 요구를 실제로
만족하는 경로를 위해, IAM 인증(SASL/OAUTHBEARER, 9098)을 지원하는 producer 바이너리를 별도로
구현해 이 폴더에 둔다.

## 배치

빌드한 바이너리를 이 경로에 `producer` 이름으로 둔다 (LFS 추적 — 루트 `.gitattributes`):

```
module-4-msk/app/producer
```

- 이 바이너리는 **IAM 전용**으로 설계됐다 — 항상 SASL/IAM(9098)으로 접속한다(TLS/IAM 런타임 전환 없음).
  제공 바이너리(TLS) ↔ 이 바이너리(IAM) 선택은 `producer_auth_mode` 변수로 결정된다.
- 그 외 동작·출력은 제공 바이너리와 동일 (`../../provided/module4/Application.md`):
  env `BOOTSTRAP_SERVERS`, `TOPIC_RAW`, `AWS_REGION`(signer 리전), 센서 JSON 을 `sensorId` 키로 발행.

## 활성화

```hcl
# terraform.tfvars
producer_auth_mode = "iam"
```

이러면 (1) 클러스터가 IAM 전용으로 좁혀지고(`unauthenticated=false`), (2) 이 바이너리가
S3 `bin/app` 로 스테이징돼 producer EC2 가 9098 로 발행한다. 기본값 `tls` 는 제공 바이너리
+ 9094 로 채점 검증이 끝난 경로를 그대로 쓴다.
