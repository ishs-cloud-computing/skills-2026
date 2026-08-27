# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# destroy 가 private 서브넷·VPC 삭제에서 DependencyViolation 으로 멈출 때 쓴다.
# VPC 배치 Lambda(sensor_consumer)·MSK ESM 이 만든 Hyperplane ENI 가 terraform state 밖에
# 남아 서브넷을 잡고 있는 게 원인 — 함수·ESM 이 지워져도 ENI 회수가 수 분~수십 분 늦다.
# VPC ID 는 terraform output 에서 읽는다(사람이 vpc-xxxx 를 옮겨 적지 않는다).
param(
  [string]$VpcId,
  [string]$Region = "ap-northeast-1"
)

$env:AWS_DEFAULT_REGION = $Region

if (-not $VpcId) {
  $VpcId = terraform -chdir=terraform output -raw vpc_id 2>$null
}
if (-not $VpcId) {
  Write-Error "VPC ID 를 못 구했다 — terraform state 에 vpc_id output 이 없다(오래된 apply일 수 있음). -VpcId <vpc-xxxx> 로 직접 넘기거나 'terraform apply -refresh-only' 로 state 를 갱신한다."
  exit 2
}

Write-Host "=== VPC ($VpcId) ENI 정리를 시작한다 ===" -ForegroundColor Cyan

# ==========================================
# 1) 이 모듈의 Lambda Kafka 트리거 삭제
#    terraform destroy 가 정상 진행 중이면 이미 지워져 있는 게 보통이다 — 없으면 그냥 스킵.
# ==========================================
Write-Host "`n[1단계] Lambda Kafka 트리거 조회 및 삭제 중..." -ForegroundColor Cyan
$fns = "wsc2026-sensor-consumer", "wsc2026-sensor-alert-consumer"
$mappings = foreach ($fn in $fns) {
  aws lambda list-event-source-mappings --function-name $fn `
    --query "EventSourceMappings[?contains(EventSource, 'kafka')].[UUID,FunctionName,State]" --output text 2>$null
}
$mappings = $mappings | Where-Object { $_ -match '\S' }

if ($mappings) {
  foreach ($line in @($mappings)) {
    $uuid, $funcName, $state = $line -split "\s+"
    Write-Host "-> 발견된 트리거 UUID: $uuid (함수: $funcName, 상태: $state)" -ForegroundColor Yellow
    aws lambda delete-event-source-mapping --uuid $uuid | Out-Null
  }
  Write-Host "-> 트리거 삭제 요청 완료. AWS 가 정리할 때까지 30초 대기..." -ForegroundColor Gray
  Start-Sleep -Seconds 30
} else {
  Write-Host "-> 삭제할 Lambda Kafka 트리거가 없다 (destroy 가 이미 지웠을 가능성)." -ForegroundColor Green
}

# ==========================================
# 2) 이 VPC 서브넷을 쓰는 Lambda 의 VPC 연결 해제
# ==========================================
Write-Host "`n[2단계] VPC 내 Lambda 함수 연결 해제 중..." -ForegroundColor Cyan
$subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" --query "Subnets[].SubnetId" --output text
if ($subnets) {
  $subnetList = $subnets -split "\s+"
  $lambdaFunctions = aws lambda list-functions --query "Functions[?VpcConfig.SubnetIds].FunctionName" --output text
  if ($lambdaFunctions) {
    foreach ($func in @($lambdaFunctions -split "\s+" | Where-Object { $_ })) {
      $funcSubnets = aws lambda get-function-configuration --function-name $func --query "VpcConfig.SubnetIds" --output text
      $match = $false
      foreach ($s in ($funcSubnets -split "\s+")) {
        if ($subnetList -contains $s) { $match = $true }
      }
      if ($match) {
        Write-Host "-> 함수 [$func] 가 이 VPC 를 사용 중이다. VPC 연동 해제..." -ForegroundColor Yellow
        aws lambda update-function-configuration --function-name $func --vpc-config SubnetIds=[],SecurityGroupIds=[] | Out-Null
      }
    }
    Write-Host "-> Lambda VPC 해제 요청 완료. ENI 비활성화 대기 30초..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
  } else {
    Write-Host "-> VPC 내 Lambda 함수가 없다." -ForegroundColor Green
  }
}

# ==========================================
# 3) 남아있는 ENI 일괄 detach + delete
# ==========================================
Write-Host "`n[3단계] 남아있는 ENI 정리 진행..." -ForegroundColor Cyan
$enis = aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VpcId" `
  --query "NetworkInterfaces[].[NetworkInterfaceId,Status,Attachment.AttachmentId,Description]" --output text

if ($enis) {
  foreach ($line in @($enis -split "`r?`n" | Where-Object { $_ -match '\S' })) {
    $parts = $line -split "\s+"
    $eni = $parts[0]
    $status = $parts[1]
    $att = $parts[2]
    $description = ($parts[3..($parts.Length - 1)]) -join " "

    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host "처리 중인 ENI: $eni (상태: $status)"
    if ($description) { Write-Host "설명: $description" -ForegroundColor Gray }

    # ela-attach 로 시작하고 설명에 Lambda 가 아닌 다른 관리형 서비스(VPCE 등)의 ENI 는
    # 그 서비스를 먼저 지워야 해제된다 — 여기서 강제로 건드리면 그 서비스가 깨진다.
    if ($att -like "ela-attach-*" -and $description -notlike "*AWS Lambda*") {
      Write-Host "[패스] 다른 AWS 관리형 서비스(예: VPCE)의 ENI다. 해당 서비스를 먼저 수동 삭제해야 한다." -ForegroundColor DarkYellow
      continue
    }

    if ($status -eq "in-use" -and $att -and $att -ne "None") {
      Write-Host "  -> Attachment $att 연결 해제 요청 (Force)..."
      $detachResult = aws ec2 detach-network-interface --attachment-id $att --force 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Host "  [실패] Detach 에러: $detachResult" -ForegroundColor Red
        continue
      }

      # available 상태로 전이될 때까지 최대 60초 대기
      $retry = 0
      while ($retry -lt 12) {
        Start-Sleep -Seconds 5
        $currentStatus = aws ec2 describe-network-interfaces --network-interface-ids $eni --query "NetworkInterfaces[0].Status" --output text 2>$null
        if ($currentStatus -eq "available") {
          Write-Host "  -> 상태 변경 완료 (available)" -ForegroundColor Green
          break
        }
        $retry++
      }
    }

    Write-Host "  -> ENI 최종 삭제 진행 중..."
    $deleteResult = aws ec2 delete-network-interface --network-interface-id $eni 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  [실패] Delete 에러: $deleteResult" -ForegroundColor Red
    } else {
      Write-Host "  [성공] ENI 삭제 완료" -ForegroundColor Green
    }
  }
} else {
  Write-Host "-> 이 VPC 에 더 이상 남아있는 ENI 가 없다." -ForegroundColor Green
}

Write-Host "`n=== 정리 완료. terraform destroy 를 다시 돌린다 ===" -ForegroundColor Cyan
