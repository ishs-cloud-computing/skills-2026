# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

<#
.SYNOPSIS
  부착 KIT README 의 "## VERIFY" 블록을 그대로 실행한다.

.DESCRIPTION
  KIT README 는 전부 같은 순서(USE WHEN -> CHANGE -> CHECK -> RUN -> VERIFY -> TROUBLESHOOT)로
  돼 있고 VERIFY 절에 PowerShell 블록이 들어 있다. 그 블록은 `terraform output` 을 쓰므로
  KIT 을 부착한 세트의 terraform 디렉터리에서 실행해야 한다.

  VERIFY 는 SCORE 가 아니다. 여기서 전부 통과해도 세트 공식 mark.md / mark*.sh 는 따로 돌린다.

.EXAMPLE
  cd set-07/task-1/terraform
  ../../../shared/scripts/verify-kit.ps1 waf kms cw-alarms

.EXAMPLE
  # 실행하지 않고 명령만 본다
  ../../../shared/scripts/verify-kit.ps1 s3-hardening -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Kit,

    # VERIFY 블록을 실행할 디렉터리. terraform output 이 나오는 곳이어야 한다.
    [string]$Path = '.',

    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''

$AddonRoot = Join-Path $PSScriptRoot '..\addons'

function Get-VerifyBlock {
    param([string]$Readme)

    $inVerify = $false
    $inFence = $false
    $lines = @()

    foreach ($line in (Get-Content -LiteralPath $Readme)) {
        if ($line -match '^## ') { $inVerify = ($line -match '^##\s+VERIFY'); continue }
        if (-not $inVerify) { continue }
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { $lines += $line }
    }
    return ($lines -join "`n")
}

if (-not $Kit) {
    Write-Host "사용법: verify-kit.ps1 <kit> [<kit> ...] [-Path <terraform 디렉터리>] [-DryRun]`n"
    Write-Host "VERIFY 블록이 있는 KIT:"
    Get-ChildItem $AddonRoot -Directory | Sort-Object Name | ForEach-Object {
        $readme = Join-Path $_.FullName 'README.md'
        if ((Test-Path $readme) -and (Get-VerifyBlock $readme)) { Write-Host "  $($_.Name)" }
    }
    exit 0
}

Push-Location $Path
try {
    foreach ($name in $Kit) {
        $readme = Join-Path $AddonRoot "$name\README.md"
        Write-Host "`n===== $name" -ForegroundColor Cyan

        if (-not (Test-Path $readme)) {
            Write-Host "  KIT 이 없다: $readme" -ForegroundColor Red
            continue
        }

        $block = Get-VerifyBlock $readme
        if (-not $block) {
            Write-Host "  VERIFY 에 실행 가능한 블록이 없다 — README 를 직접 읽어라." -ForegroundColor Yellow
            continue
        }

        if ($DryRun) { Write-Host $block; continue }

        # 한 줄이 실패해도 나머지 KIT 검증은 계속한다. 실패한 줄은 stderr 에 그대로 남는다.
        try { Invoke-Expression $block }
        catch { Write-Host "  실패: $_" -ForegroundColor Red }
    }
}
finally { Pop-Location }

Write-Host "`nVERIFY 는 기능 확인이다. 점수는 세트의 mark.md / mark*.sh 로 따로 확인한다." -ForegroundColor DarkGray
