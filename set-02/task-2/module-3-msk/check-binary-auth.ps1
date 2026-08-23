# 대회 제공 producer 바이너리가 MSK IAM 인증(SASL/IAM)을 할 수 있는지, 아니면 비인증 TLS
# 전용인지 판별한다. 방법: 문자열 마커 검색 (근거·재현: BINARY-ANALYSIS.md).
# 판정은 MSK IAM 전용 마커(결정적)만 근거로 한다 — SigV4 계열 문자열(보조)은 S3·SSM 등
# 아무 AWS SDK 호출만 있어도 박히므로, 그것만으로 iam 판정하면 접속 불가 바이너리를
# iam 모드로 배포하는 오탐이 난다.
# 주의: 문자열 휴리스틱 — 마커가 난독화되면 미탐 가능. 확정은 BINARY-ANALYSIS.md 의 r2/pclntab.
param([string]$Path = "$PSScriptRoot/../provided/module3/app")

if (-not (Test-Path $Path)) { Write-Error "바이너리 없음: $Path"; exit 2 }

# 결정적 마커 — MSK IAM 구현에만 존재. 하나라도 있으면 iam 판정.
#   AWS_MSK_IAM: SaslHandshake 로 브로커에 보내는 메커니즘 이름 — 와이어 필수라 숨길 수 없다
#   aws-msk-iam-sasl-signer: 공식 signer 라이브러리 모듈 경로 (Go pclntab 에 남는다)
$decisive = @(
  @{ Str = "AWS_MSK_IAM";             Desc = "IAM SASL 메커니즘 이름 (와이어 필수)" }
  @{ Str = "aws-msk-iam-sasl-signer"; Desc = "IAM SASL signer 라이브러리" }
)
# 보조 마커 — IAM 구현의 필요조건이지만 다른 AWS SDK 사용으로도 박힌다. 판정에 쓰지 않는다.
$generic = @(
  @{ Str = "kafka-cluster";           Desc = "MSK IAM SigV4 서비스명" }
  @{ Str = "AWS4-HMAC-SHA256";        Desc = "SigV4 알고리즘" }
  @{ Str = "aws4_request";            Desc = "SigV4 요청 스코프" }
)

# 바이너리를 1바이트=1문자(ISO-8859-1)로 읽어 부분 문자열 검색 — PS 5.1/7 공통 동작
$bytes = [System.IO.File]::ReadAllBytes($Path)
$text = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($bytes)

Write-Host "대상: $Path"
Write-Host "----"
$decisiveFound = 0
$genericFound = 0
foreach ($m in $decisive) {
  if ($text.Contains($m.Str)) {
    Write-Host ("  [발견] {0,-24} {1} (결정적)" -f $m.Str, $m.Desc)
    $decisiveFound++
  } else {
    Write-Host ("  [없음] {0,-24} {1} (결정적)" -f $m.Str, $m.Desc)
  }
}
foreach ($m in $generic) {
  if ($text.Contains($m.Str)) {
    Write-Host ("  [발견] {0,-24} {1} (보조)" -f $m.Str, $m.Desc)
    $genericFound++
  } else {
    Write-Host ("  [없음] {0,-24} {1} (보조)" -f $m.Str, $m.Desc)
  }
}
Write-Host "----"
if ($decisiveFound -gt 0) {
  Write-Host "판정: 결정적 IAM 마커 ${decisiveFound}건 -> SASL/IAM(9098). producer_auth_mode=iam 사용 가능."
  exit 0
} else {
  if ($genericFound -gt 0) {
    Write-Host "참고: 보조(SigV4) 마커 ${genericFound}건은 다른 AWS API 호출 흔적일 수 있어 판정에 쓰지 않는다."
  }
  Write-Host "판정: 결정적 IAM 마커 0건 -> 비인증 TLS(9094) 전용. producer_auth_mode=tls 로 둘 것."
  exit 1
}
