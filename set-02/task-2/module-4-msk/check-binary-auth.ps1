# 대회 제공 producer 바이너리가 MSK IAM 인증(SASL/IAM)을 할 수 있는지, 아니면 비인증 TLS
# 전용인지 판별한다. 방법: IAM 인증 구현에 반드시 평문으로 박히는 마커 문자열을 검색한다
# (근거·재현: BINARY-ANALYSIS.md). 대회 배포 바이너리 자체를 재검증하는 용도 — 결과와
# 무관하게 배포는 이 바이너리 그대로, 항상 TLS(9094) 다.
# ponytail: 문자열 휴리스틱 — 마커가 난독화되면 오탐 가능. 확정은 BINARY-ANALYSIS.md 의 r2/pclntab.
param([string]$Path = "$PSScriptRoot/../provided/module4/app")

if (-not (Test-Path $Path)) { Write-Error "바이너리 없음: $Path"; exit 2 }

# Desc/Str — IAM 인증이면 반드시 하나 이상 평문으로 존재해야 하는 문자열
$markers = @(
  @{ Str = "aws-msk-iam-sasl-signer"; Desc = "IAM SASL signer 라이브러리" }
  @{ Str = "AWS_MSK_IAM";             Desc = "IAM SASL 메커니즘 이름" }
  @{ Str = "kafka-cluster";           Desc = "MSK IAM SigV4 서비스명" }
  @{ Str = "AWS4-HMAC-SHA256";        Desc = "SigV4 알고리즘" }
  @{ Str = "aws4_request";            Desc = "SigV4 요청 스코프" }
)

# 바이너리를 1바이트=1문자(ISO-8859-1)로 읽어 부분 문자열 검색 — PS 5.1/7 공통 동작
$bytes = [System.IO.File]::ReadAllBytes($Path)
$text = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($bytes)

Write-Host "대상: $Path"
Write-Host "----"
$found = 0
foreach ($m in $markers) {
  if ($text.Contains($m.Str)) {
    Write-Host ("  [발견] {0,-24} {1}" -f $m.Str, $m.Desc)
    $found++
  } else {
    Write-Host ("  [없음] {0,-24} {1}" -f $m.Str, $m.Desc)
  }
}
Write-Host "----"
if ($found -gt 0) {
  Write-Host "판정: IAM 인증 지원 -> SASL/IAM(9098) 가능."
  exit 0
} else {
  Write-Host "판정: IAM 마커 0건 -> 비인증 TLS(9094) 전용 (배포 경로와 일치, 정상)."
  exit 1
}
