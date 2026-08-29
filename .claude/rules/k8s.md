---
paths:
  - "**/k8s/**"
  - "**/helm/**"
---

- `k8s/` 는 apply 가 알파벳 순이다. **순서 의존 파일에만 번호 prefix** (`00-namespace.yaml`). 도메인이 많으면 `app/`·`monitoring/`·`logging/` 서브디렉토리로 묶는다.
- manifest 주석은 **관련 근거 또는 설계 의도만** 쓴다. 무엇을 하는지 되풀이하지 않는다.
- 채점 스크립트가 읽는 필드(label·annotation·이름·네임스페이스)는 중복돼 보여도 제거하지 않는다.
- ServiceAccount 의 `eks.amazonaws.com/role-arn` annotation 이 채점 대상이면 **IRSA** 다. Pod Identity 는 그 annotation 을 만들지 않는다 → [eks-grading.md](../context/eks-grading.md)
- `**/rendered/`·`**/*.rendered.yaml` 은 `.gitignore` 대상이다. 렌더링 산출물을 커밋하지 않는다.
