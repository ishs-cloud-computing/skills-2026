# 디렉토리·파일 배치·문서 분할

> CLAUDE.md 라우팅에서 **"파일을 새로 만들 때 / 어디에 쓸지 헷갈릴 때"** 읽는다.

## 디렉토리 구조

새 세트는 `_template/` 을 `set-XX/` 로 복사해서 시작한다. `_template/` 이 구조를 보여준다.

- **task-1**: 안 쓰는 하위 디렉토리(`terraform`·`eksctl`·`k8s`·`app`)는 지운다.
- **task-2**: 모듈 기본 4개. `module-N/` 을 `module-N-<name>/` 으로 개명하고 안 쓰는 하위만 지운다. 당일 모듈이 추가되면 `module-4/` 를 복사해 5·6을 만든다.
- `eksctl/` 은 `terraform/` 과 같은 레벨.
- `provided/` 는 대회 제공 원본. **수정 금지** — 구현은 `module-N-<name>/` 에 따로 만든다.

## 코드에서 안 드러나는 배치 규칙

- **`k8s/`**: apply 가 알파벳 순이라 순서 의존 파일에 번호 prefix (`00-namespace.yaml`). 도메인이 많으면 `app/`·`monitoring/`·`logging/` 서브디렉토리로 묶고, **번호는 순서 의존 파일에만** 붙인다.
- **`shared/addons/<kit>/`**: 세트에 복사(COPY)해서 쓰는 추가 문항 대응 KIT. addon 디렉터리 자체는 `init`/`apply` 대상이 아니다.
- **`shared/scripts/`**: `discover.ps1`(리소스 ID 수집) · `verify-kit.ps1`(KIT VERIFY 일괄) · `foul-check.ps1`(제출 전 금지 조항 검사).

## 문서 삼분할

같은 정보를 두 곳에 쓰지 않는다. **한 문서에 종류를 섞지 않는다.**

| 문서 | 종류 | 담는 것 | 금지 |
| --- | --- | --- | --- |
| `README.md` | How-to (런북) | 실행·배포·teardown 절차. 명령형 단계 | **"왜" 를 쓰지 않는다** |
| `NOTES.md` | 개발자 노트 | 함정·기각한 대안·삽질·실측 소요시간·결정 로그·정정 로그·채점 커버리지 | 절차를 다시 쓰지 않는다 (README 참조) |
| `ARCHITECTURE.md` (`task-3/`) | Explanation | 왜 이 아키텍처인가. 설계 이유·트레이드오프 | 명령·절차 |

`NOTES.md` 결정 로그 형식: `맥락 / 채택 / 기각 / 대가`. **기각 대안은 실재하는 것만** 적는다.

### `docs/` 는 이 저장소에 없다

CLAUDE.md·커맨드 문서가 오랫동안 `docs/CONTRIBUTING.md` 와 `docs/src/content/docs/setlist/...` 를 가리켰지만 **이 저장소에는 `docs/` 디렉토리가 한 번도 커밋된 적이 없다.** 발행되는 Explanation 사이트는 별도 저장소다 (README "학습 가이드" 절의 링크).

따라서 이 저장소에서 작업할 때:

- 설계 근거는 `NOTES.md`(세트별) 또는 `task-3/ARCHITECTURE.md` 에 남긴다.
- `docs/` 경로를 새로 만들지 않는다. 사이트 발행용 문서를 쓸 일이 생기면 **대상 저장소를 먼저 확인**한다.
- 기여 규약(브랜치·커밋·SPDX·라이선스)은 루트 [`CONTRIBUTING.md`](../../CONTRIBUTING.md) 다.
