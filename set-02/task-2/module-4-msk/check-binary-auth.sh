#!/usr/bin/env bash
# 대회 제공 producer 바이너리가 MSK IAM 인증(SASL/IAM)을 할 수 있는지, 아니면 비인증 TLS
# 전용인지 판별한다. 방법: IAM 인증 구현에 반드시 평문으로 박히는 마커 문자열을 검색한다
# (근거·재현: BINARY-ANALYSIS.md). 대회 배포 바이너리 자체를 재검증하는 용도 — 결과와
# 무관하게 배포는 이 바이너리 그대로, 항상 TLS(9094) 다.
# ponytail: 문자열 휴리스틱 — 마커가 난독화되면 오탐 가능. 확정은 BINARY-ANALYSIS.md 의 r2/pclntab.
set -euo pipefail

BIN="${1:-$(dirname "$0")/../provided/module4/app}"
[ -f "$BIN" ] || { echo "바이너리 없음: $BIN" >&2; exit 2; }

# desc|marker — IAM 인증이면 반드시 하나 이상 평문으로 존재해야 하는 문자열
MARKERS=(
  "IAM SASL signer 라이브러리|aws-msk-iam-sasl-signer"
  "IAM SASL 메커니즘 이름|AWS_MSK_IAM"
  "MSK IAM SigV4 서비스명|kafka-cluster"
  "SigV4 알고리즘|AWS4-HMAC-SHA256"
  "SigV4 요청 스코프|aws4_request"
)

echo "대상: $BIN"
echo "----"
found=0
for m in "${MARKERS[@]}"; do
  desc="${m%%|*}"; str="${m##*|}"
  n=$(grep -a -c -- "$str" "$BIN" || true)
  if [ "${n:-0}" -gt 0 ]; then
    printf "  [발견] %-24s %s (%s건)\n" "$str" "$desc" "$n"
    found=$((found + 1))
  else
    printf "  [없음] %-24s %s\n" "$str" "$desc"
  fi
done
echo "----"
if [ "$found" -gt 0 ]; then
  echo "판정: IAM 인증 지원 → SASL/IAM(9098) 가능."
  exit 0
else
  echo "판정: IAM 마커 0건 → 비인증 TLS(9094) 전용 (배포 경로와 일치, 정상)."
  exit 1
fi
