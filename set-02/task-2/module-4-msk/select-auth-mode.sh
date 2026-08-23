#!/usr/bin/env bash
# 대회 당일 producer_auth_mode 를 판별한다.
# 판별 기준은 하나다 — 그날 지급된 제공 바이너리가 IAM 인증을 할 수 있는가.
#   할 수 있으면  iam : 제공 바이너리로 과제지 요구(IAM 전용 9098)를 그대로 만족한다.
#   못 하면       tls : 제공 바이너리 외 배포가 불가하므로 비인증 9094 우회밖에 없다.
# 2026-08-17 시점의 배포본은 IAM signer 가 없어 tls 로 판정된다(BINARY-ANALYSIS.md).
# 출제 측이 바이너리를 교체하면 판정이 뒤집히므로 대회 당일 반드시 다시 돌린다.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROVIDED="${1:-$HERE/../provided/module4/app}"
[ -f "$PROVIDED" ] || { echo "제공 바이너리 없음: $PROVIDED" >&2; exit 2; }

"$HERE/check-binary-auth.sh" "$PROVIDED"
provided_supports_iam=$?

echo
echo "===================================================================="
if [ "$provided_supports_iam" -eq 0 ]; then
  echo "판정: 제공 바이너리가 IAM 인증 가능 → iam (정통 경로, 기본값)"
  echo
  echo "  terraform apply"
  echo
  echo "주의: s3.tf 의 app_source 는 iam 모드에서 자체 바이너리(app/producer)를 올린다."
  echo "      제공 바이너리가 IAM 을 지원하면 자체 바이너리를 쓸 이유가 없으므로,"
  echo "      -var 'iam_producer_binary_path=../../provided/module4/app' 로 제공본을 쓴다."
else
  echo "판정: 제공 바이너리가 IAM 인증 불가 → tls (대회 제출 우회 경로)"
  echo
  echo "  terraform apply -var \"producer_auth_mode=tls\""
  echo
  echo "주의: 기본값은 iam 이므로 -var 를 빠뜨리면 자체 바이너리로 배포된다"
  echo "      (대회 제출 불가). README 'producer 인증 경로' 절 참고."
fi
echo "===================================================================="
