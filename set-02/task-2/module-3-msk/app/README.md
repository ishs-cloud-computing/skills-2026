# app — 자체 IAM 인증 producer

2026-08-17 시점의 제공 바이너리(`../../provided/module4/app`)는 SASL/IAM signer 가 없어
9094 비인증 TLS 로만 접속한다(`../BINARY-ANALYSIS.md`). 9094 TLS 는 전송 구간 암호화일 뿐
인증이 없어, 과제지 "MSK 는 IAM 인증을 통해서만 접근" 요구를 만족하지 못한다. 그래서 IAM
인증(SASL/OAUTHBEARER, 9098)을 지원하는 producer 를 따로 만들어 이 폴더에 뒀다.

이 경로가 기본값(`producer_auth_mode=iam`)이다. 대회는 제공 바이너리 외 배포를 허용하지
않으므로, 당일 제출에 이 바이너리를 쓸 수 있는지는 **그날 지급된 제공 바이너리의 판정에
달렸다** — 판별은 `../select-auth-mode.ps1`, 두 경로 비교는 `../README.md` 의
"producer 인증 경로" 절.

## 산출물

`producer` (Go, x86-64 static ELF) — **저장소에 이미 들어 있는 검증된 바이너리다. 별도 빌드가
필요 없다.** LFS 추적(루트 `.gitattributes`). 확인:

```powershell
# 본 PC (PowerShell) — cwd: module-3-msk
.\check-binary-auth.ps1 app\producer
# 판정: IAM 인증 지원 → SASL/IAM(9098). producer_auth_mode=iam 사용 가능.
```

```bash
# 리눅스 로컬 — cwd: module-3-msk
./check-binary-auth.sh app/producer
```

같은 스크립트를 제공 바이너리(`../provided/module4/app`)에 돌리면 IAM 마커 0건이 나온다 —
두 바이너리의 차이가 이 한 줄로 드러난다.

- 이 바이너리는 **IAM 전용**이다 — 항상 SASL/IAM(9098)으로 접속한다(TLS/IAM 런타임 전환 없음).
  제공 바이너리(TLS) ↔ 이 바이너리(IAM) 선택은 `producer_auth_mode` 변수로 결정된다.
- 그 외 동작·출력은 제공 바이너리와 동일 (`../../provided/module4/Application.md`):
  env `BOOTSTRAP_SERVERS`, `TOPIC_RAW`, `AWS_REGION`(signer 리전), 센서 JSON 을 `sensorId` 키로 발행.

## 활성화

`terraform.tfvars` 의 `producer_auth_mode = "iam"` 이 기본값이라 `terraform apply` 만 하면
이 바이너리가 S3 `bin/app` 로 스테이징돼 producer EC2 가 9098 로 발행한다.
