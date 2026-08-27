#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors
# 대회 제공 producer 바이너리가 MSK IAM 인증(SASL/IAM)을 할 수 있는지, 아니면 비인증 TLS
# 전용인지 판별한다. 방법: 문자열 마커 검색 (근거·재현: BINARY-ANALYSIS.md).
# 판정은 MSK IAM 전용 마커(결정적)만 근거로 한다 — SigV4 계열 문자열(보조)은 S3·SSM 등
# 아무 AWS SDK 호출만 있어도 박히므로, 그것만으로 iam 판정하면 접속 불가 바이너리를
# iam 모드로 배포하는 오탐이 난다.
# 주의: 문자열 휴리스틱 — 마커가 난독화되면 미탐 가능. 확정은 BINARY-ANALYSIS.md 의 r2/pclntab.
set -euo pipefail

BIN="${1:-$(dirname "$0")/../provided/module3/app}"
[ -f "$BIN" ] || { echo "바이너리 없음: $BIN" >&2; exit 2; }

# 결정적 마커 — MSK IAM 구현에만 존재. 하나라도 있으면 iam 판정.
#   AWS_MSK_IAM: SaslHandshake 로 브로커에 보내는 메커니즘 이름 — 와이어 필수라 숨길 수 없다
#   aws-msk-iam-sasl-signer: 공식 signer 라이브러리 모듈 경로 (Go pclntab 에 남는다)
DECISIVE=(
  "IAM SASL 메커니즘 이름 (와이어 필수)|AWS_MSK_IAM"
  "IAM SASL signer 라이브러리|aws-msk-iam-sasl-signer"
)
# 보조 마커 — IAM 구현의 필요조건이지만 다른 AWS SDK 사용으로도 박힌다. 판정에 쓰지 않는다.
GENERIC=(
  "MSK IAM SigV4 서비스명|kafka-cluster"
  "SigV4 알고리즘|AWS4-HMAC-SHA256"
  "SigV4 요청 스코프|aws4_request"
)

echo "대상: $BIN"
echo "----"
decisive_found=0
generic_found=0
for m in "${DECISIVE[@]}"; do
  desc="${m%%|*}"; str="${m##*|}"
  n=$(grep -a -c -- "$str" "$BIN" || true)
  if [ "${n:-0}" -gt 0 ]; then
    printf "  [발견] %-24s %s (%s건, 결정적)\n" "$str" "$desc" "$n"
    decisive_found=$((decisive_found + 1))
  else
    printf "  [없음] %-24s %s (결정적)\n" "$str" "$desc"
  fi
done
for m in "${GENERIC[@]}"; do
  desc="${m%%|*}"; str="${m##*|}"
  n=$(grep -a -c -- "$str" "$BIN" || true)
  if [ "${n:-0}" -gt 0 ]; then
    printf "  [발견] %-24s %s (%s건, 보조)\n" "$str" "$desc" "$n"
    generic_found=$((generic_found + 1))
  else
    printf "  [없음] %-24s %s (보조)\n" "$str" "$desc"
  fi
done
echo "----"
if [ "$decisive_found" -gt 0 ]; then
  echo "판정: 결정적 IAM 마커 ${decisive_found}건 → SASL/IAM(9098). producer_auth_mode=iam 사용 가능."
  exit 0
else
  if [ "$generic_found" -gt 0 ]; then
    echo "참고: 보조(SigV4) 마커 ${generic_found}건은 다른 AWS API 호출 흔적일 수 있어 판정에 쓰지 않는다."
  fi
  echo "판정: 결정적 IAM 마커 0건 → 비인증 TLS(9094) 전용. producer_auth_mode=tls 로 둘 것."
  exit 1
fi
