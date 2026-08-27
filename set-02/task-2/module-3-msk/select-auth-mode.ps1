# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# 대회 당일 producer_auth_mode 를 판별한다.
# 판별 기준은 하나다 — 그날 지급된 제공 바이너리가 IAM 인증을 할 수 있는가.
#   할 수 있으면  iam : 제공 바이너리로 과제지 요구(IAM 전용 9098)를 그대로 만족한다.
#   못 하면       tls : 제공 바이너리 외 배포가 불가하므로 비인증 9094 우회밖에 없다.
# 2026-08-17 시점의 배포본은 IAM signer 가 없어 tls 로 판정된다(BINARY-ANALYSIS.md).
# 출제 측이 바이너리를 교체하면 판정이 뒤집히므로 대회 당일 반드시 다시 돌린다.
param([string]$ProvidedPath = "$PSScriptRoot/../provided/module3/app")

if (-not (Test-Path $ProvidedPath)) { Write-Error "제공 바이너리 없음: $ProvidedPath"; exit 2 }

& "$PSScriptRoot/check-binary-auth.ps1" $ProvidedPath
$providedSupportsIam = ($LASTEXITCODE -eq 0)

Write-Host ""
Write-Host "===================================================================="
if ($providedSupportsIam) {
  Write-Host "판정: 제공 바이너리가 IAM 인증 가능 -> iam (정통 경로, 기본값)"
  Write-Host ""
  Write-Host "  terraform apply"
  Write-Host ""
  Write-Host "주의: s3.tf 의 app_source 는 iam 모드에서 자체 바이너리(app/producer)를 올린다."
  Write-Host "      제공 바이너리가 IAM 을 지원하면 자체 바이너리를 쓸 이유가 없으므로,"
  Write-Host "      -var 'iam_producer_binary_path=../../provided/module3/app' 로 제공본을 쓴다."
} else {
  Write-Host "판정: 제공 바이너리가 IAM 인증 불가 -> tls (대회 제출 우회 경로)"
  Write-Host ""
  Write-Host "  terraform apply -var `"producer_auth_mode=tls`""
  Write-Host ""
  Write-Host "주의: 기본값은 iam 이므로 -var 를 빠뜨리면 자체 바이너리로 배포된다"
  Write-Host "      (대회 제출 불가). README 'producer 인증 경로' 절 참고."
}
Write-Host "===================================================================="
