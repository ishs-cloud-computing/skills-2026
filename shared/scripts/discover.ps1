# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

<#
.SYNOPSIS
  한 리전의 기존 리소스 ID 를 전수 스캔해 .env 파일로 떨군다.

.DESCRIPTION
  KIT README 의 FAST 절과 CLI 명령은 <vpc-id>·<sg-id>·<ALB ARN> 같은 실제 ID 를 요구한다.
  KIT-INDEX 의 세트별 대조표는 Terraform 주소라 CLI 로 붙일 때는 못 쓰고, terraform output 은
  outputs.tf 에 선언한 것만 나온다. 이 스크립트는 계정에 실제로 있는 것을 그대로 긁는다.

  출력은 KEY=value 한 줄 형식이라 PowerShell 과 bash 양쪽에서 읽힌다 (파일 머리에 로드 명령이 적힌다).
  대회 규칙상 bastion·CloudShell 은 연결이 끊기면 환경이 날아가므로 이 파일을 같이 올려 둔다.

  읽기 전용이다. 아무것도 만들지 않고 아무것도 바꾸지 않는다.

.EXAMPLE
  shared\scripts\discover.ps1
  shared\scripts\discover.ps1 -Region ap-southeast-1

.EXAMPLE
  # 모듈별 리전이 다른 2과제
  'ap-northeast-2','ap-southeast-1','us-east-1' | ForEach-Object { shared\scripts\discover.ps1 -Region $_ }
#>
[CmdletBinding()]
param(
    [string]$Region = (aws configure get region),

    # 기본값은 addon.<리전>.env — 리전마다 파일이 갈려 이름이 안 겹친다.
    [string]$Out,

    # AWS 호출 없이 파싱 로직만 검사한다. 계정이 비어 있어도 이건 돈다.
    [switch]$SelfTest
)

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''

if ($SelfTest) {
    $lines = [System.Collections.Generic.List[string]]::new()
    function Key([string]$s) { ($s -replace '[^A-Za-z0-9]', '_').ToUpper() }
    function Emit([string]$prefix, [string]$name, [string]$val) {
        if ($val -and $val -ne 'None' -and $name) { $lines.Add("${prefix}_$(Key $name)=$val") }
    }
    function Rows($text) {
        $out = [System.Collections.Generic.List[object]]::new()
        foreach ($line in @($text)) { if ($line) { $out.Add([string[]]($line -split "`t")) } }
        return , $out.ToArray()
    }

    $fail = 0
    function Assert($cond, $msg) { if ($cond) { Write-Host "  ok   $msg" -ForegroundColor DarkGray } else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ } }

    Assert ((Key 'wsc2026-skills-vpc') -eq 'WSC2026_SKILLS_VPC') 'Key: 하이픈을 밑줄로'
    Assert ((Key 'alias/unicorn-kms-app') -eq 'ALIAS_UNICORN_KMS_APP') 'Key: 슬래시도 밑줄로'

    Assert ((Rows $null).Count -eq 0) 'Rows: 빈 출력은 빈 배열'
    $r = Rows @("a`tb`tc", "d`te`tf")
    Assert ($r.Count -eq 2 -and $r[1][2] -eq 'f') 'Rows: 여러 행을 탭으로 분해'
    $r1 = Rows "x`ty"
    Assert ($r1.Count -eq 1 -and $r1[0][0] -eq 'x') 'Rows: 한 행도 배열로 감싼다'

    Emit VPC 'my-vpc' 'vpc-123'
    Emit VPC 'no-value' ''
    Emit EC2_PUBIP 'private-only' 'None'
    Assert ($lines.Count -eq 1 -and $lines[0] -eq 'VPC_MY_VPC=vpc-123') 'Emit: 빈 값과 None 은 버린다'

    $arn = 'arn:aws:elasticloadbalancing:ap-northeast-2:1:loadbalancer/app/unicorn-app/abc123'
    Assert (($arn -replace '^.*:loadbalancer/', '') -eq 'app/unicorn-app/abc123') 'ALB_DIM: put-metric-alarm dimension 형태'

    if ($fail) { Write-Host "`n$fail 개 실패" -ForegroundColor Red; exit 1 }
    Write-Host "`nSelfTest 통과" -ForegroundColor Green
    exit 0
}

if (-not $Region) { Write-Host "리전을 못 정했다. -Region 으로 넘기거나 aws configure set region 을 먼저." -ForegroundColor Red; exit 1 }
if (-not $Out) { $Out = "addon.$Region.env" }

$acct = aws sts get-caller-identity --query Account --output text 2>$null
if (-not $acct) { Write-Host "자격증명이 없다. aws sts get-caller-identity 부터 확인해라." -ForegroundColor Red; exit 1 }

$lines = [System.Collections.Generic.List[string]]::new()

function Key([string]$s) { ($s -replace '[^A-Za-z0-9]', '_').ToUpper() }

function Emit([string]$prefix, [string]$name, [string]$val) {
    if ($val -and $val -ne 'None' -and $name) { $lines.Add("${prefix}_$(Key $name)=$val") }
}

# aws --output text 는 행을 탭으로 나눈다.
# 행이 1개일 때 PowerShell 이 바깥 배열을 풀어버려 열이 행처럼 순회되므로, 통째로 감싸서 돌려준다.
function Rows($text) {
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @($text)) { if ($line) { $out.Add([string[]]($line -split "`t")) } }
    return , $out.ToArray()
}

function AwsR { aws --region $Region @args 2>$null }

$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$lines.Add("# discover.ps1  $ts  region=$Region  account=$acct")
$lines.Add("# bash:        set -a; . ./$Out; set +a")
$lines.Add("# powershell:  Get-Content $Out | Where-Object { `$_ -match '=' -and `$_ -notmatch '^#' } | ForEach-Object { `$k, `$v = `$_ -split '=', 2; Set-Item env:`$k `$v }")
$lines.Add("REGION=$Region")
$lines.Add("ACCOUNT_ID=$acct")

# --- 네트워크 ---
foreach ($r in Rows (AwsR ec2 describe-vpcs --filters Name=is-default,Values=false --query 'Vpcs[].[Tags[?Key==`Name`].Value|[0],VpcId,CidrBlock]' --output text)) {
    $n = if ($r[0] -and $r[0] -ne 'None') { $r[0] } else { $r[1] }
    Emit VPC $n $r[1]; Emit VPCCIDR $n $r[2]
}
foreach ($r in Rows (AwsR ec2 describe-subnets --query 'Subnets[].[Tags[?Key==`Name`].Value|[0],SubnetId,AvailabilityZone]' --output text)) {
    $n = if ($r[0] -and $r[0] -ne 'None') { $r[0] } else { $r[1] }
    Emit SUBNET $n $r[1]; Emit SUBNETAZ $n $r[2]
}
foreach ($r in Rows (AwsR ec2 describe-route-tables --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],RouteTableId]' --output text)) {
    $n = if ($r[0] -and $r[0] -ne 'None') { $r[0] } else { $r[1] }
    Emit RTB $n $r[1]
}
foreach ($r in Rows (AwsR ec2 describe-security-groups --query 'SecurityGroups[].[GroupName,GroupId]' --output text)) { Emit SG $r[0] $r[1] }

# 묶음 — create-vpc-endpoint --subnet-ids / --route-table-ids 에 그대로 넣는다 (공백 구분)
foreach ($tier in 'pub', 'priv', 'public', 'private') {
    $ids = (AwsR ec2 describe-subnets --filters "Name=tag:Name,Values=*$tier*" --query 'Subnets[].SubnetId' --output text)
    if ($ids) { $lines.Add("SUBNETS_$(Key $tier)=$((($ids -split '\s+') | Where-Object { $_ }) -join ' ')") }
    $rt = (AwsR ec2 describe-route-tables --filters "Name=tag:Name,Values=*$tier*" --query 'RouteTables[].RouteTableId' --output text)
    if ($rt) { $lines.Add("RTBS_$(Key $tier)=$((($rt -split '\s+') | Where-Object { $_ }) -join ' ')") }
}

# --- EKS ---
foreach ($c in ((AwsR eks list-clusters --query 'clusters[]' --output text) -split '\s+' | Where-Object { $_ })) {
    Emit EKS $c $c
    foreach ($r in Rows (AwsR eks describe-cluster --name $c --query 'cluster.[endpoint,version,resourcesVpcConfig.vpcId,identity.oidc.issuer,accessConfig.authenticationMode]' --output text)) {
        Emit EKS_ENDPOINT $c $r[0]; Emit EKS_VERSION $c $r[1]; Emit EKS_VPC $c $r[2]
        Emit EKS_OIDC $c $r[3]; Emit EKS_AUTHMODE $c $r[4]
    }
    $ng = (AwsR eks list-nodegroups --cluster-name $c --query 'nodegroups[]' --output text)
    if ($ng) { Emit EKS_NODEGROUPS $c ((($ng -split '\s+') | Where-Object { $_ }) -join ',') }
}

# --- 로드밸런서 ---
foreach ($r in Rows (AwsR elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,LoadBalancerArn,DNSName,Scheme]' --output text)) {
    Emit ALB_ARN $r[0] $r[1]; Emit ALB_DNS $r[0] $r[2]; Emit ALB_SCHEME $r[0] $r[3]
    # put-metric-alarm --dimensions Name=LoadBalancer,Value=<여기> 에 들어가는 형태
    Emit ALB_DIM $r[0] ($r[1] -replace '^.*:loadbalancer/', '')
}
foreach ($r in Rows (AwsR elbv2 describe-target-groups --query 'TargetGroups[].[TargetGroupName,TargetGroupArn]' --output text)) { Emit TG $r[0] $r[1] }

# --- CloudFront (글로벌) : 채점이 Comment 로 배포를 찾으므로 Comment 를 키로 쓴다 ---
foreach ($r in Rows (aws cloudfront list-distributions --query 'DistributionList.Items[].[Comment,Id,DomainName]' --output text 2>$null)) {
    $n = if ($r[0] -and $r[0] -ne 'None') { $r[0] } else { $r[1] }
    Emit CF_ID $n $r[1]; Emit CF_DOMAIN $n $r[2]
}

# --- 데이터 / 스토리지 / 컴퓨팅 ---
foreach ($t in ((AwsR dynamodb list-tables --query 'TableNames[]' --output text) -split '\s+' | Where-Object { $_ })) { Emit DDB $t $t }
foreach ($b in ((aws s3api list-buckets --query 'Buckets[].Name' --output text 2>$null) -split '\s+' | Where-Object { $_ })) { Emit S3 $b $b }
foreach ($f in ((AwsR lambda list-functions --query 'Functions[].FunctionName' --output text) -split '\s+' | Where-Object { $_ })) { Emit LAMBDA $f $f }
foreach ($r in Rows (AwsR ecr describe-repositories --query 'repositories[].[repositoryName,repositoryUri]' --output text)) { Emit ECR $r[0] $r[1] }
foreach ($r in Rows (AwsR kms list-aliases --query 'Aliases[?starts_with(AliasName,`alias/`) && !starts_with(AliasName,`alias/aws/`)].[AliasName,TargetKeyId]' --output text)) {
    Emit KMS ($r[0] -replace '^alias/', '') $r[1]
}
foreach ($a in ((AwsR sns list-topics --query 'Topics[].TopicArn' --output text) -split '\s+' | Where-Object { $_ })) { Emit SNS ($a -split ':')[-1] $a }
foreach ($u in ((AwsR sqs list-queues --query 'QueueUrls[]' --output text) -split '\s+' | Where-Object { $_ })) { Emit SQS ($u -split '/')[-1] $u }
foreach ($g in ((AwsR logs describe-log-groups --query 'logGroups[].logGroupName' --output text) -split '\s+' | Where-Object { $_ })) { Emit LOGS $g $g }

foreach ($r in Rows (AwsR ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,PrivateIpAddress,PublicIpAddress]' --output text)) {
    $n = if ($r[0] -and $r[0] -ne 'None') { $r[0] } else { $r[1] }
    Emit EC2 $n $r[1]; Emit EC2_PRIVIP $n $r[2]; Emit EC2_PUBIP $n $r[3]
}

$lines | Set-Content -Encoding utf8 -LiteralPath $Out
$vars = @($lines | Where-Object { $_ -notmatch '^#' })
Write-Host "wrote $Out  ($($vars.Count) vars, region=$Region)"
$vars | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host "`n로드 방법은 파일 머리 두 줄에 적혀 있다. bastion·CloudShell 에 같이 올려 둔다." -ForegroundColor DarkGray

# 조회 실패는 개별로 무시한다(2>$null). 못 찾은 리소스는 빈 출력 자체가 신호다.
exit 0
