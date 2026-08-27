#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
# destroy 가 private 서브넷·VPC 삭제에서 DependencyViolation 으로 멈출 때 쓴다.
# VPC 배치 Lambda(sensor_consumer)·MSK ESM 이 만든 Hyperplane ENI 가 terraform state 밖에
# 남아 서브넷을 잡고 있는 게 원인 — 함수·ESM 이 지워져도 ENI 회수가 수 분~수십 분 늦다.
# VPC ID 는 terraform output 에서 읽는다(사람이 vpc-xxxx 를 옮겨 적지 않는다).
set -uo pipefail

VPCID="${1:-}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-1}"

if [ -z "$VPCID" ]; then
  VPCID=$(terraform -chdir=terraform output -raw vpc_id 2>/dev/null)
fi
if [ -z "$VPCID" ]; then
  echo "VPC ID 를 못 구했다 — terraform state 에 vpc_id output 이 없다(오래된 apply일 수 있음)." >&2
  echo "인자로 직접 넘기거나(./teardown-eni.sh vpc-xxxx) 'terraform apply -refresh-only' 로 state 를 갱신한다." >&2
  exit 2
fi

echo "=== VPC ($VPCID) ENI 정리를 시작한다 ==="

# ==========================================
# 1) 이 모듈의 Lambda Kafka 트리거 삭제
#    terraform destroy 가 정상 진행 중이면 이미 지워져 있는 게 보통이다 — 없으면 그냥 스킵.
# ==========================================
echo
echo "[1단계] Lambda Kafka 트리거 조회 및 삭제 중..."
mappings=""
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  out=$(aws lambda list-event-source-mappings --function-name "$fn" \
    --query "EventSourceMappings[?contains(EventSource, 'kafka')].[UUID,FunctionName,State]" --output text 2>/dev/null)
  [ -n "$out" ] && mappings="${mappings}${out}"$'\n'
done

if [ -n "$(echo "$mappings" | tr -d '[:space:]')" ]; then
  echo "$mappings" | while read -r uuid funcName state; do
    [ -z "$uuid" ] && continue
    echo "-> 발견된 트리거 UUID: $uuid (함수: $funcName, 상태: $state)"
    aws lambda delete-event-source-mapping --uuid "$uuid" >/dev/null
  done
  echo "-> 트리거 삭제 요청 완료. AWS 가 정리할 때까지 30초 대기..."
  sleep 30
else
  echo "-> 삭제할 Lambda Kafka 트리거가 없다 (destroy 가 이미 지웠을 가능성)."
fi

# ==========================================
# 2) 이 VPC 서브넷을 쓰는 Lambda 의 VPC 연결 해제
# ==========================================
echo
echo "[2단계] VPC 내 Lambda 함수 연결 해제 중..."
subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query "Subnets[].SubnetId" --output text)
if [ -n "$subnets" ]; then
  lambda_functions=$(aws lambda list-functions --query "Functions[?VpcConfig.SubnetIds].FunctionName" --output text)
  if [ -n "$lambda_functions" ]; then
    for func in $lambda_functions; do
      func_subnets=$(aws lambda get-function-configuration --function-name "$func" --query "VpcConfig.SubnetIds" --output text)
      match=0
      for s in $func_subnets; do
        for target in $subnets; do
          [ "$s" = "$target" ] && match=1
        done
      done
      if [ "$match" = "1" ]; then
        echo "-> 함수 [$func] 가 이 VPC 를 사용 중이다. VPC 연동 해제..."
        aws lambda update-function-configuration --function-name "$func" --vpc-config SubnetIds=[],SecurityGroupIds=[] >/dev/null
      fi
    done
    echo "-> Lambda VPC 해제 요청 완료. ENI 비활성화 대기 30초..."
    sleep 30
  else
    echo "-> VPC 내 Lambda 함수가 없다."
  fi
fi

# ==========================================
# 3) 남아있는 ENI 일괄 detach + delete
# ==========================================
echo
echo "[3단계] 남아있는 ENI 정리 진행..."
enis=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPCID" \
  --query "NetworkInterfaces[].[NetworkInterfaceId,Status,Attachment.AttachmentId,Description]" --output text)

if [ -n "$enis" ]; then
  echo "$enis" | while read -r eni status att description; do
    [ -z "$eni" ] && continue
    echo "--------------------------------------------------"
    echo "처리 중인 ENI: $eni (상태: $status)"
    [ -n "$description" ] && echo "설명: $description"

    # ela-attach 로 시작하고 설명에 Lambda 가 아닌 다른 관리형 서비스(VPCE 등)의 ENI 는
    # 그 서비스를 먼저 지워야 해제된다 — 여기서 강제로 건드리면 그 서비스가 깨진다.
    case "$att" in
      ela-attach-*)
        case "$description" in
          *"AWS Lambda"*) ;;
          *)
            echo "[패스] 다른 AWS 관리형 서비스(예: VPCE)의 ENI다. 해당 서비스를 먼저 수동 삭제해야 한다."
            continue
            ;;
        esac
        ;;
    esac

    if [ "$status" = "in-use" ] && [ -n "$att" ] && [ "$att" != "None" ]; then
      echo "  -> Attachment $att 연결 해제 요청 (Force)..."
      if ! aws ec2 detach-network-interface --attachment-id "$att" --force >/dev/null 2>&1; then
        echo "  [실패] Detach 에러 — 다음 ENI 로 넘어간다"
        continue
      fi

      # available 상태로 전이될 때까지 최대 60초 대기
      for _ in $(seq 1 12); do
        sleep 5
        current_status=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" \
          --query "NetworkInterfaces[0].Status" --output text 2>/dev/null)
        if [ "$current_status" = "available" ]; then
          echo "  -> 상태 변경 완료 (available)"
          break
        fi
      done
    fi

    echo "  -> ENI 최종 삭제 진행 중..."
    if aws ec2 delete-network-interface --network-interface-id "$eni" 2>&1; then
      echo "  [성공] ENI 삭제 완료"
    else
      echo "  [실패] Delete 에러"
    fi
  done
else
  echo "-> 이 VPC 에 더 이상 남아있는 ENI 가 없다."
fi

echo
echo "=== 정리 완료. terraform destroy 를 다시 돌린다 ==="
