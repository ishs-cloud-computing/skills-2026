#!/usr/bin/env bash
# PostToolUse(Edit|Write): .tf 편집 시 해당 파일 fmt + 디렉토리 validate.
# settings.json은 git으로 공유되지만 이 스크립트는 Unix 전용 — Windows에서는 조용히 no-op.

is_windows() {
  # 1) Git Bash/MSYS2/Cygwin 셸이 설정하는 표식
  [ -n "${MSYSTEM:-}" ] && return 0
  # 2) Windows가 모든 프로세스에 물려주는 %OS%
  [ "${OS:-}" = "Windows_NT" ] && return 0
  # 3) 커널 이름 (uname 자체가 없으면 빈 문자열 → 매칭 안 됨)
  case "$(uname -s 2>/dev/null)" in
  CYGWIN* | MINGW* | MSYS* | Windows*) return 0 ;;
  esac
  return 1
}
is_windows && exit 0

file=$(jq -r '.tool_input.file_path // empty')

[[ $file == *.tf ]] || exit 0             # .tf 외 확장자 무시 (.tfvars 포함)
[[ $file == */.terraform/* ]] && exit 0   # 프로바이더 캐시는 건드리지 않음
[ -f "$file" ] || exit 0

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not on PATH - skipping fmt/validate" >&2
  exit 0
fi

dir=$(dirname "$file")
terraform fmt "$file" >/dev/null 2>&1

# init 여부는 .terraform/ 존재가 아니라 validate 에러 문구로 판별한다
# (프로바이더 없는 모듈은 init해도 .terraform/이 생기지 않아 오탐).
# init은 프로바이더 수백 MB를 받으므로 훅이 자동 실행하지 않는다.
if out=$(terraform -chdir="$dir" validate -no-color 2>&1); then
  exit 0
elif [[ $out == *"terraform init"* ]]; then
  msg="terraform validate skipped: $dir is not initialized - run 'terraform init'"
else
  msg="terraform validate FAILED in $dir:
$out"
fi

# exit 0 + JSON: systemMessage는 사용자에게, additionalContext는 Claude에게.
# exit 1은 stderr 첫 줄만 노출되어 여러 줄인 validate 에러가 잘린다.
jq -n --arg m "$msg" '{
  systemMessage: $m,
  hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}
}'
exit 0
