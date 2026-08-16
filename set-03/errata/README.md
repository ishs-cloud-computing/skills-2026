# set-03 정정 원본 — 세트 귀속 안내

`errata/` 안의 txt 는 **원본이라 수정하지 않는다.** 이 파일은 어느 항목이 이 세트 몫인지만 정리한다. 판정 근거와 반영 내역은 [`../task-1/NOTES.md`](../task-1/NOTES.md) 정정 로그에 있다.

## 이 세트의 정본

| 파일 | 내용 |
|---|---|
| `수정사항.txt` | 11-3 All Pod, App Logs 형식 기준, 9-3 `created_at` 을 `date` 기준 검증 |
| `수정사항(1).txt` | 11-4 HighLatency Alert 채점 삭제, Reference02 로그 `level`, 11-2 DataSource 이름, `booking_id` 예시값 |

`수정사항(1).txt` 는 원래 `set-02/errata/수정사항.txt` 로 잘못 놓여 있던 파일이다(2026-08-16 이관). 담긴 4문답이 전부 11절·Alert 항목을 전제하는데 set-02 채점지는 대분류 1~10 이라 대응 항목이 없다.

## `질의답변-취합-20260816.txt` — 두 세트가 섞인 문서

set-02 와 같은 파일을 양쪽에 둔다. **이 세트 몫은 아래 6건이다.**

| 취합본 항목 | 이 세트 번호 | 판정 |
|---|---|---|
| `01` Grafana Pod CPU/Memory 는 All Pod | 11-3 | 영향없음 (`dashboard.json` `namespace` 변수 기본값 All) |
| `02` App Logs 는 채점기준표 형식 기준 | 11-3 | 영향없음 (`fluent-bit.yaml` 이 `level` 유도) |
| `03` / `[9-3]` `created_at` 을 curl 직전 `date` 기준 1분 이내 | 9-3 | 수정완료 (채점지·채점 스크립트 전사본) |
| `04` / `[5-4 / 11-1 / 11-3]` 테스트 파드 생성·`sleep` 을 11-3 수동 실행으로 | 11-1 / 11-3 | 수정완료 (전사본) |
| `05` / `[6-1]` `static/ PASS` 객체 채점 제외 | 6-1 | 수정완료 (예상 출력) |
| `06` / `[11-3]` 패널 이름 채점 제외 | 11-3 | 영향없음 (요구 완화) |

나머지 항목(`[1-1-A]`, `[2-1-A]`, `[7]` GSI, `[7-2]`, `[10-1~4 (12)]`)은 **set-02 몫**이다. → [`../../set-02/errata/README.md`](../../set-02/errata/README.md)

## 구현에 남긴 것

`11-4` 채점 항목은 삭제됐지만 **`k8s/monitoring/prometheus-rules.yaml` 의 HighLatency 룰은 유지한다** — 과제지(`task.md:175`) Prometheus Alert 표가 여전히 그 룰을 요구하고, 삭제된 건 Firing 확인 항목뿐이다.
