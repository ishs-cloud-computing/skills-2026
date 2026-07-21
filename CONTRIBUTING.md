# 프로젝트 기여 가이드

## Index

- [기여하는 방법](#기여하는-방법)
- [Issue 및 Pull Request 생성](#issue-및-pull-request-생성)
- [Commit & Branch convention](#commit--branch-convention)
- [AI Guideline](#ai-guideline)
- [라이선스 및 기여자 표기](#라이선스-및-기여자-표기)

## 기여하는 방법

다음의 기여를 환영합니다:

🐛 버그 수정 (잘못된 리소스 참조, tfvars 오류 등)  
⚡️ 모듈 리팩토링 및 성능/비용 개선  
✨ 새로운 세트/과제/모듈 추가  
📝 문서화 (README, 아키텍처 다이어그램, 변수 설명)

## Issue 및 Pull Request 생성

### Issue

- 버그나 기능 제안은 GitHub Issue로 등록해주세요.
- `terraform plan` 실패, 리소스 간 의존성 문제는 **재현 가능한 최소 예제**(minimal `.tf` 스니펫)와 함께 올려주시면 빠르게 확인할 수 있습니다.

### Pull Request

1. 작업 전에 Issue를 먼저 등록하고, 진행 중이라는 기록을 남겨주세요 (중복 작업 방지)
2. 새 브랜치에서 작업 후 PR을 생성합니다. `main` 브랜치로 직접 push하지 않습니다.
3. PR 본문에는 다음을 포함해주세요:
    - 무엇을 바꾸었는지
    - 왜 바꾸었는지
    - 테스트/검증 방법 (`terraform fmt`·`validate`·`plan` 통과, 해당 세트 `mark.sh`/`markN.sh` 실행 결과)
4. tfstate·`.terraform/`·`outputs.json`은 커밋하지 않으며, `.tfvars`에 시크릿 값이 포함되지 않았는지 반드시 확인 후 PR을 올려주세요.
5. 병합시 squash merge로 병합.

## Commit & Branch convention

- 브랜치명: `set-09/task-1`, `fix-describe`
- Commit 메시지: 명령형 어법 사용 (예: "Add EKS private cluster module", "Fix VPC CIDR overlap")

## AI Guideline

Terraform 코드를 포함해 AI 도구 (Claude 등) 활용을 환영하지만, 다음을 지켜주세요:

- 과제의 내용을 이해하여야 합니다.
- AI가 생성한 서비스를 이해할 수 있어야 합니다.
- 실제 apply 후 채점 결과를 검증해야합니다.

## 라이선스 및 기여자 표기

이 저장소에 기여하면, 귀하의 기여물이 **Apache License 2.0**으로 배포되는 데
동의하는 것으로 간주됩니다. 한번 이 라이선스로
기여한 코드는 철회할 수 없으며, 기여자가 동아리를 떠나더라도 저장소는 유지됩니다.

- 새 소스 파일에는 상단에 SPDX 헤더를 넣어주세요:

```
  # SPDX-License-Identifier: Apache-2.0
  # Copyright 2026 The ISHS Cloud Computing Authors
```

- 기존 파일의 저작권·라이선스 표기는 삭제하지 마세요.
- 첫 기여 시 `AUTHORS` 파일에 본인을 추가해주세요.
- **본인이 작성하지 않은 코드**는 반입 전 라이선스 호환성을 확인하고, 원저작자 표기를 유지하세요. 호환되는 서드파티 코드를 포함할 경우 루트의 `NOTICE` 파일에 attribution을 추가합니다.
