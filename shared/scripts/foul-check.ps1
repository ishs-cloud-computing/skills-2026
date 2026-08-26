# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

<#
.SYNOPSIS
  제출 전 자가검사 — 금지 조항 위반과 불필요 리소스 잔재를 훑는다.

.DESCRIPTION
  DAY-OF 9절(채점 직전) 체크리스트 중 명령으로 확인 가능한 것만 모았다.
  출력은 판단 재료다. 0 이 아니라고 전부 감점은 아니고, 과제지가 금지한 항목이 0 이 아니면
  그 항목은 통째로 0점이 된다. 종이 과제지의 "~할 수 없습니다 / ~는 금지합니다" 와 대조한다.

  검사 항목
    1. running EC2      — 3과제는 수가 적을수록 고득점, 작업용 bastion 잔재는 감점
    2. 타 리전 잔재     — EC2 / EKS 가 다른 리전에 남아 있는가
    3. IAM 광범위 권한  — 고객 관리형 정책의 "Action": "*" / "Principal": "*"
    4. 0.0.0.0/0 인바운드 보안그룹
    5. EKS 채점 접근    — authenticationMode 와 access entry principal

.EXAMPLE
  shared/scripts/foul-check.ps1
  shared/scripts/foul-check.ps1 -Regions ap-northeast-2,ap-southeast-1
#>
[CmdletBinding()]
param(
    # 훑을 리전. 기본값은 준비한 세트들이 쓰는 리전 전부.
    [string[]]$Regions = @('ap-northeast-2', 'ap-northeast-1', 'ap-southeast-1', 'us-east-1'),

    # EKS 채점 주체로 기대하는 principal ARN 조각 (IAM User 이름 등). 넣으면 access entry 에서 찾아준다.
    [string]$GraderPrincipal
)

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''

function Head($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Warn($t) { Write-Host "  $t" -ForegroundColor Yellow }
function Ok($t) { Write-Host "  $t" -ForegroundColor DarkGray }

$id = aws sts get-caller-identity --query '[Account,Arn]' --output text 2>$null
if (-not $id) { Write-Host "자격증명이 없다. aws sts get-caller-identity 부터 확인해라." -ForegroundColor Red; exit 1 }
Write-Host "계정/주체: $id"
Write-Host "리전: $($Regions -join ', ')"

Head "1·2. running EC2 / EKS (리전별)"
foreach ($r in $Regions) {
    $ec2 = aws ec2 describe-instances --region $r `
        --filters Name=instance-state-name,Values=running `
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,InstanceType]' `
        --output text 2>$null
    $eks = aws eks list-clusters --region $r --query 'clusters[]' --output text 2>$null

    $n = if ($ec2) { ($ec2 -split "`n").Count } else { 0 }
    if ($n -eq 0 -and -not $eks) { Ok "${r}: EC2 0 · EKS 없음"; continue }

    Write-Host "  ${r}: EC2 $n" -ForegroundColor White
    if ($ec2) { $ec2 -split "`n" | ForEach-Object { Warn "    $_" } }
    if ($eks) { Warn "    EKS: $eks" }
}
Write-Host "  -> 과제지가 요구하지 않은 EC2(작업용 bastion 포함)는 감점이다. 채점 중에는 새로 시작할 수 없으니 지우기 전에 CloudShell 경로를 먼저 검증한다." -ForegroundColor DarkGray

Head "3. IAM 고객 관리형 정책의 Action / Principal 와일드카드"
$found = $false
aws iam list-policies --scope Local --query 'Policies[].[Arn,DefaultVersionId]' --output text 2>$null |
ForEach-Object {
    if (-not $_) { return }
    $arn, $ver = $_ -split "`t"
    $doc = aws iam get-policy-version --policy-arn $arn --version-id $ver --query PolicyVersion.Document --output json 2>$null
    # Resource:"*" 는 ec2:Describe* 처럼 불가피한 경우가 많아 보지 않는다.
    if ($doc -match '"(Action|Principal)"\s*:\s*"\*"') { Warn $arn; $script:found = $true }
}
if (-not $found) { Ok "없음" }

Head "4. 0.0.0.0/0 인바운드 보안그룹"
$found = $false
foreach ($r in $Regions) {
    $sg = aws ec2 describe-security-groups --region $r `
        --filters Name=ip-permission.cidr,Values=0.0.0.0/0 `
        --query 'SecurityGroups[].[GroupName,GroupId]' --output text 2>$null
    if ($sg) { $sg -split "`n" | ForEach-Object { Warn "${r}  $_" }; $found = $true }
}
if (-not $found) { Ok "없음" }
else { Write-Host "  -> ALB/CloudFront 앞단은 정상이다. 22/3306 등 관리 포트가 열려 있는지만 본다." -ForegroundColor DarkGray }

Head "5. EKS 채점 접근 (authenticationMode · access entry)"
$any = $false
foreach ($r in $Regions) {
    foreach ($c in (aws eks list-clusters --region $r --query 'clusters[]' --output text 2>$null) -split "\s+") {
        if (-not $c) { continue }
        $any = $true
        $mode = aws eks describe-cluster --region $r --name $c --query 'cluster.accessConfig.authenticationMode' --output text 2>$null
        Write-Host "  ${r}/${c}  authenticationMode=$mode"
        $entries = aws eks list-access-entries --region $r --cluster-name $c --query 'accessEntries[]' --output text 2>$null
        if ($entries) { ($entries -split "\s+") | Where-Object { $_ } | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
        else { Warn "    access entry 없음 — aws-auth 경로인지 확인" }
        if ($GraderPrincipal) {
            if ($entries -match [regex]::Escape($GraderPrincipal)) { Ok "    채점 주체 '$GraderPrincipal' 있음" }
            else { Write-Host "    채점 주체 '$GraderPrincipal' 을 access entry 에서 못 찾았다" -ForegroundColor Red }
        }
    }
}
if (-not $any) { Ok "클러스터 없음" }
Write-Host "  -> 완료 조건은 '클러스터가 있다' 가 아니라 일반 CloudShell 에서 update-kubeconfig 한 줄 뒤 kubectl get nodes 가 되는 것이다." -ForegroundColor DarkGray

Write-Host "`n명령으로 못 보는 항목은 DAY-OF 9절에서 눈으로 확인한다 — 이름 정확 일치, 부하 테스트 중지, 종이 과제지 금지 조항." -ForegroundColor DarkGray
