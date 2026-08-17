# 제공 producer 바이너리 분석 — MSK IAM 인증 불가

과제지는 "MSK 클러스터는 IAM 인증을 통해서만 접근 가능해야 한다"(task.md 3번 MSK)고 요구하고, Producer 는 대회가 제공한 바이너리(`../provided/module4/app`, 수정 금지)를 그대로 실행하게 되어 있다(task.md 4번 EC2, Application.md). 이 바이너리가 실제로 IAM 인증을 할 수 있는지 리버싱으로 검증한 기록이다. 아래 명령으로 누구나 재현할 수 있다.

- 대상: `../provided/module4/app` — ELF 64-bit x86-64, Go 정적 빌드(`sensor-producer`, CGO_ENABLED=0), 스트립됨
- 도구: radare2 6.1.9, Go pclntab 파싱

## 결론

IAM 인증이 가능하려면 ① 인증 구현체, ② 서명 재료, ③ 설정 코드 세 가지가 모두 있어야 한다. 세 층위를 독립적으로 검사했고 **전부 부재**다. 이 바이너리가 접속할 수 있는 경로는 9094 TLS(비인증) 또는 평문뿐이며, IAM 인증(9098)은 구조적으로 불가능하다.

| 층위 | 상태 | 재현 |
|---|---|---|
| ① IAM 인증 구현체 (`sasl.Mechanism`) | 없음 (전체 6,711개 함수 전수 확인) | 증거 1 |
| ② 수제 SigV4 서명 재료 (필수 리터럴) | 없음 (전부 0건) | 증거 2 |
| ③ SASL 설정 코드 (`Transport.SASL`) | 없음 (nil) | 증거 3 |

## 증거 1 — 인증 구현체 부재 (전체 함수 전수 검사)

pclntab 에서 전체 함수명을 복구해 SASL/AWS 관련을 검색하면, 매칭은 전부 `kafka-go` 라이브러리에 항상 딸려오는 배관 코드(`saslhandshake`, `authenticateSASL` 등)와 이름만 걸린 무관 함수(`runtime.plainError` 등)뿐이다. kafka-go 에서 SASL 을 쓰려면 `sasl.Mechanism` **구현체**(`sasl/plain`·`sasl/scram`·`aws_msk_iam`)가 링크돼야 하는데 **하나도 없다** — 인터페이스에 넘길 객체 자체가 존재하지 않는다.

빌드 의존성도 일치(`aws-msk-iam-sasl-signer-go`·`aws-sdk-go` 부재):

```
$ go version -m ../provided/module4/app | grep '\bdep\b'
	dep	github.com/klauspost/compress	v1.15.9
	dep	github.com/pierrec/lz4/v4	v4.1.15
	dep	github.com/segmentio/kafka-go	v0.4.49
```

재현 (pclntab 파싱, `go` 없이도 확인 가능):

```bash
python3 - <<'PY'
import struct, re
f = open('../provided/module4/app','rb').read()
off = -1; i = 0                            # Go 1.20+ pclntab magic 0xFFFFFFF1
while True:                                # pad2=0, quantum, ptrsize 로 진짜 헤더 검증
    i = f.find(b'\xf1\xff\xff\xff', i+1)
    if i < 0: break
    if f[i+4]==0 and f[i+5]==0 and f[i+6] in (1,2,4) and f[i+7] in (4,8):
        off = i; break
fld = lambda k: struct.unpack('<Q', f[off+8+k*8:off+16+k*8])[0]
nfunc, fnbase, pcbase = fld(0), off+fld(3), off+fld(7)
pat = re.compile(r'(?i)sasl|aws|iam|sigv4|signer|scram')
mech = re.compile(r'sasl\.(Mechanism|plain|scram|aws)', re.I)
hits = mechs = 0
for i in range(nfunc):
    eo, fo = struct.unpack('<II', f[pcbase+i*8:pcbase+i*8+8])
    no = struct.unpack('<I', f[pcbase+fo+4:pcbase+fo+8])[0]
    na = fnbase+no; name = f[na:f.index(b'\x00',na)].decode('utf-8','replace')
    if pat.search(name): hits += 1
    if mech.search(name): mechs += 1
print(f"함수 {nfunc}개 / SASL·AWS 매칭 {hits}개 / sasl.Mechanism 구현체 {mechs}개")
PY
# 기대 출력: 함수 6711개 / SASL·AWS 매칭 33개 / sasl.Mechanism 구현체 0개
```

## 증거 2 — 수제 구현 배제 (필수 리터럴 문자열 0건)

라이브러리 없이 IAM 인증을 직접 짰다면, 프로토콜상 반드시 바이너리에 평문으로 박혀 있어야 하는 문자열들이 있다. `AWS_MSK_IAM` 은 브로커에 와이어로 그대로 나가는 값이라 난독화로 숨길 수도 없다. 전부 0건:

```bash
for s in AWS_MSK_IAM AWS4-HMAC-SHA256 aws4_request kafka-cluster \
         AWS_ACCESS_KEY_ID AWS_SESSION_TOKEN 169.254.169.254 AssumeRole X-Amz- SCRAM-SHA; do
  printf '%-20s %s건\n' "$s" "$(grep -c -a -- "$s" ../provided/module4/app)"
done
# 기대: 전부 0건
```

| 문자열 | 필수 이유 |
|---|---|
| `AWS_MSK_IAM` | SASL 핸드셰이크로 전송하는 메커니즘 이름 (없으면 협상 자체 불가) |
| `AWS4-HMAC-SHA256` / `aws4_request` | SigV4 서명 페이로드 고정 문자열 |
| `kafka-cluster` | IAM 서명 대상 서비스명 |
| `169.254.169.254` | EC2 IAM 역할 자격증명(IMDS) 주소 |

## 증거 3 — 설정 코드 부재 (`main.main` 어셈블리)

`main.main` 에서 `kafka.Transport` 생성 후 필드에 쓰는 명령은 두 곳뿐이다. `SASL` 필드는 건드리지 않아 nil 로 남고, kafka-go 는 `SASL == nil` 이면 인증을 시도하지 않는다.

```
mov [rcx],      rbx    ; Dial
mov [rcx+0x48], rdx    ; TLS ← tlsConfigFor() 반환값
                       ; SASL 필드: 미기록 = nil
```

유일한 보안 설정 `main.tlsConfigFor`(0x6786c0)는 브로커 포트가 **9094**(`cmp rax, 0x2386`)일 때만 `tls.Config{MinVersion: TLS1.2}`(`mov word [rax+0x108], 0x303`)를 반환하고 그 외엔 nil(평문)을 반환한다 — 서버 인증서 검증만 하는 비인증 TLS. 재현:

```bash
r2 -2 -q -c 'af @ 0x6786c0; pdf @ 0x6786c0' ../provided/module4/app | grep -E 'cmp rax|0x2386|0x303'
# 기대: cmp rax, 0x2386  /  mov word [rax + 0x108], 0x303
```

## 결론이 배포에 미치는 영향

이 분석이 확정한 건 **"2026-08-17 시점에 배포된 이 바이너리로는 IAM 인증이 불가능하다"** 까지다. 대회는 제공 바이너리 외 배포를 허용하지 않으므로, 그날 지급된 바이너리가 같은 판정이면 제출은 9094 TLS 우회 경로가 된다. 출제 측이 바이너리를 교체하면 판정이 뒤집히므로 **대회 당일 `select-auth-mode` 로 다시 판별한다** — 이 문서의 결론을 그대로 전제하지 않는다. 저장소 기본값은 과제지 요구대로의 IAM 전용(`producer_auth_mode=iam`)이다.

두 경로의 차이·전환 절차는 [README.md](README.md) 의 "producer 인증 경로" 절. 이 분석에서만 나오는 실패 모드 하나:

- tls 경로에서 9098 을 주면 `unexpected EOF: broker appears to be expecting TLS` 로 영원히 실패한다(위 `main.tlsConfigFor` 가 9094 에서만 TLS 를 켜기 때문). 배포된 EC2 즉시 복구:
  ```bash
  sudo sed -i 's/:9098/:9094/g' /etc/systemd/system/app.service && sudo systemctl daemon-reload && sudo systemctl restart app
  ```
