---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.tftpl"
---

- 리소스 이름은 **과제지에 명시된 값과 정확히 일치**시킨다. 이름 정확 일치 채점 항목이 많다.
- `variables.tf` 에 기본값, 세트별 이름·CIDR·리전 값은 `terraform.tfvars` 로 주입한다. 바뀌기 쉬운 축(이름·CIDR·리전·인스턴스 타입·개수)은 전부 변수화.
- 채점 스크립트가 검사하는 정확한 형태를 기준으로 한다. **중복·불필요해 보여도 채점 대상 필드는 제거하지 않는다.**
- state 는 로컬(`*.tfstate`)이며 `.gitignore` 로 제외된다. tfstate·`.terraform/`·`outputs.json` 은 **절대 커밋하지 않는다.**
- `apply` 는 본 컴퓨터에서만 한다. bastion 에는 프로바이더 대신 `terraform output -json > outputs.json` 만 올려 `jq` 로 읽는다.
- 이름이 충돌해도 **사전 제공 리소스를 지우지 않는다** — 이쪽 이름 변수를 리네임해 우회한다.
- 편집하면 `PostToolUse` 훅이 `fmt` + 해당 디렉토리 `validate` 를 자동으로 돌린다. validate 에러가 뜨면 처리하고 넘어간다.
- `plan` 에 **기존 리소스 replace/delete 가 뜨면 apply 하지 않고 멈춘다.**
- Terraform 버전의 정본은 각 모듈 `versions.tf`/`providers.tf` 의 `required_version` 이다. 새 모듈도 같은 자리에 선언한다.
- 커밋 전 `restore-placeholders` 스킬로 개인 실습값(선수번호·비밀번호·버킷 suffix) 혼입을 확인한다.
