---
paths:
  - "set-*/task-*/**"
---

아키텍처 선택이 바뀌면 커밋 전에 해당 과제의 NOTES.md 결정 로그에 append 한다.
"현재 상태"(task-2는 "모듈 현황")가 코드와 어긋나면 지우고 다시 쓴다. append 금지.
task-2: 결정 로그 항목 앞에 [module-N] 태그를 붙인다. 채점은 mark/mark2-N.sh 기준으로 해당 모듈만 대조한다.
provided/는 대회 제공 원본이다. 수정하지 않는다.
