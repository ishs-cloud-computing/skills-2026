# set-07 / task-2

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.
> 모듈 4개 고정. 각 모듈은 독립적이다.

## 모듈 현황
<!-- 덮어쓴다. 코드와 어긋난 칸은 고쳐 쓴다. -->

| 모듈 | 이름 | 채점 커버 | 미해결 |
|------|------|-----------|--------|
| 1 | nosql | 6/6 (mark1.sh 전 항목 통과) | 없음 |
| 2 | cdn-function | 6/6 (mark2.sh 전 항목 통과) | 없음 |
| 3 | eks-scaling | 7/7 (mark3.sh 전 항목 통과) | 없음 |
| 4 | container-logging | 6/6 (mark4.sh 전 항목 통과, 7.5/7.5) | 없음 |

### module-1 채점 커버리지 (mark1.sh ↔ 구현)
<!-- [x] apply 후 mark1.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-07-26 실채점 결과로 전 항목 확정 -->

- [x] 1-1-A reservation 테이블 — 실채점: 이름·PK/SK·Streams·PAY_PER_REQUEST·PITR ENABLED 전부 기대값 출력
- [x] 1-2-A GSI + audit 테이블 — 실채점: gsi-user-reservations(HASH user_id/RANGE reserved_at, ALL) + audit PK event_id 정확 일치
- [x] 1-3-A Lambda + ESM — 실채점: python3.13/30/reservation-table/Enabled 정확 일치
- [x] 1-4-A EC2 :8080 — 실채점: Public IP 조회 + healthcheck 200
- [x] 1-5-A 조건부 쓰기 — 실채점: 200/409/409/200, 본문 일치 (본문·코드 줄바꿈 분리는 jsonify trailing newline — 지급 app.py 고유 동작)
- [x] 1-6-A Streams·sparse·audit — 실채점: 1 / ["reserved",true] / 1 / 0(sparse 확인) / 2, 전부 기대값

#### module-1 함정 (실채점에서 발견)

- **log group 선존재 충돌**: 첫 apply가 `/aws/lambda/bigbae-nosql-reservation-audit` already exists로 실패 →
  `aws logs delete-log-group --log-group-name /aws/lambda/bigbae-nosql-reservation-audit --region ap-southeast-1` 후 재apply로 해결.
  대회 당일 재배포 시 같은 충돌 가능 — destroy 없이 재apply 하는 상황이면 이 명령을 먼저.

### module-2 채점 커버리지 (mark2.sh ↔ 구현)
<!-- [x] apply 후 mark2.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-07-26 실채점 결과로 전 항목 확정 -->

- [x] 2-1-A S3 버킷 — 실채점: 버킷명·오브젝트 2개·PAB·정책 전부 true (정책 검사 2개 값이 기대 출력과 달리 두 줄로 나오나 부분 일치 항목이라 통과)
- [x] 2-2-A KVS + 함수 — 실채점: 키 3개 값·ReqFn/ResFn DEPLOYED cloudfront-js-2.0·KVS 연결 true, 정확 일치
- [x] 2-3-A Distribution — 실채점: whitelist x-sp-ab / 0 300 3600 / redirect-to-https / OAC·cache policy true / 함수 2개, 정확 일치
- [x] 2-4-A 쿠키 강제 — 실채점: cookie_a_b_body true true, no_setcookie true true, HTTP→HTTPS 30x true true
- [x] 2-5-A 무작위 할당·보존 — 실채점: 배정 a, 본문·Max-Age·Path·재방문 유지·Set-Cookie 부재 전부 true (viewer-request 가 세운 assigned 헤더가 viewer-response 에 보이는 것 실증됨)
- [x] 2-6-A KVS 동적 반영 — 실채점: weight 1.0→/version-b, 0.0→/version-a, 0.3 복원 확인

#### module-2 함정 (구현 중 발견)

- **js-2.0 은 함수 인자 안의 await 금지**: `parseFloat(await kvs.get('weight'))` 가
  `SyntaxError: await in arguments not supported` 로 실행 시에만 죽는다 — CreateFunction(apply)은 검증 없이 통과.
  증상은 전 요청 503 + `x-cache: FunctionThrottledError` (라벨만 보면 스로틀로 오인).
  진단은 `aws cloudfront test-function --stage LIVE` 가 정답 (FunctionErrorMessage 에 행 번호까지 나옴).
  규칙: await 는 항상 `const x = await …` 단독 문장으로.

- **JS 리터럴 치환 범위**: 함수 소스(`terraform/cloudfront/*.js`)는 정적 파일이라 변수 미적용.
  쿠키명 `x-sp-ab`·헤더명 `x-sp-ab-assigned`·KVS 키명(`weight`/`version_a`/`version_b`)·`Max-Age=86400` 이
  바뀌면 req-fn.js·res-fn.js 를 직접 수정해야 하고, 쿠키명은 `ab_cookie_name` 변수(cache policy)와 함께 바꿔야 한다.
- **mark2.sh 가 weight 를 out-of-band 로 변경**(2-6, 종료 시 0.3 복원): 채점 직후 terraform plan 을 돌리면
  KVS 키 drift 가 보일 수 있다. 복원까지 끝났으면 무시.

### module-3 채점 커버리지 (mark3.sh ↔ 구현)
<!-- [x] apply 후 mark3.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-07-31 실채점 결과로 전 항목 확정 -->

- [x] 3-1-A SQS Queue — 실채점: skm-order-queue URL 기대값 출력
- [x] 3-2-A Cluster+NG — 실채점: 1.35 ACTIVE / t3.medium 1 1 1 / instanceName 필드로 Name 태그 확인됨
- [x] 3-3-A Deployment — 실채점: pod 가 skm-app-nodepool 노드에 배치·1 8080 500m 512Mi·env 3개 정확 일치
- [x] 3-4-A KEDA — 실채점: keda-operator Running / 1 5 aws-sqs-queue 5 정확 일치
- [x] 3-5-A Karpenter — 실채점: WhenEmptyOrUnderutilized 60s / t3.medium,t3.small / taint 1 / nodeclass 정확 일치
- [x] 3-6-A Scale-out — 실채점: Max Ready Pods 5·Max App Nodes 2 (설계상 상한과 동일: maxReplicaCount 5, 용량 계산상 노드 2대)
- [x] 3-7-A Scale-in — 실채점: purge 후 150초 창 내 Final Pods 1·Final Nodes 1 (scaleDown behavior 오버라이드 유효 실증).
  단 이때 안정화 15초 기준 ~140초 소요 — 2026-08-01 정정("2분 내")에 맞춰 안정화 0 으로 변경했고, 재배포 후 도달 시각 재실측 필요

#### module-3 함정 (구현 중 발견)

- **MNG `tags` 는 EC2 인스턴스에 전파 안 됨**: 노드 Name 태그 채점(3-2)은 eksctl `instanceName` 필드로만 충족된다.
  set-05 의 `tags: {Name: ...}` 패턴은 해당 항목이 미채점이라 안 들켰을 뿐 여기서는 실패한다.
- **KEDA chart 는 기본 tolerations 가 빈 배열**: addon NG 가 CriticalAddonsOnly taint 라 `--set-json tolerations=[...]` 누락 시
  keda pod 전부 Pending → 3-4 실패. 설치 직후 `kubectl get pods -n keda` 로 3개 Running 확인.
- **env 는 정확히 3개만**: 채점 3-3 이 컨테이너 env 전체를 sort 덤프해 비교한다. 디버그용 env 하나만 추가해도 실점.
- **zsh 에서 `"$VAR:latest"` 는 이미지명을 깨뜨린다** (실배포에서 발견): zsh 는 `$VAR:l` 을 csh-style 소문자
  modifier 로 해석해 `"$ECR_URL:latest"` → `<url 소문자화>atest` 가 된다 → ImagePullBackOff (`...processoratest`).
  변수 뒤에 `:` 가 붙으면 반드시 `"${VAR}:latest"` 중괄호. 부수: `${!v}` 간접 확장은 bash 전용(zsh bad substitution),
  대화형 붙여넣기에서 `exit` 는 터미널을 종료시키고 이후 줄도 이미 버퍼에 있어 가드가 안 됨 —
  linux 런북 스니펫은 zsh/bash 겸용 + if/else 게이트로 작성한다 (bash 전제 금지, 사용자 로컬 셸은 zsh).
- **linux 런북의 CloudShell 단계 번호 건너뛰기** (실배포에서 발견): README.linux.md 가 CloudShell 단계(3: 이미지 push)를
  서두 한 줄로만 언급하고 번호를 2→4 로 건너뛰어, 순서대로 따라가면 push 누락 → 6단계 배포가 ImagePullBackOff.
  → CloudShell 단계도 번호 자리에 stub 섹션으로 표시하도록 수정. 다른 모듈 linux 런북도 같은 규칙 적용.
- **Karpenter helm --wait 무한 대기** (실배포에서 발견): chart 기본 replicas 2 + required podAntiAffinity(hostname)
  + nodeAffinity 로 자기 nodepool 노드 배제 → addon 노드 1대에선 두 번째 pod 영구 Pending, `--wait` 가 안 끝난다.
  `--set replicas=1` 필수. 행 상태에서 중단하면 release 가 `pending-upgrade` 로 잠겨 재-upgrade 가
  "another operation is in progress" 로 막힘 → `helm uninstall karpenter -n kube-system` 후 재설치.
- **채점 전 상시 상태**: Pod 1개·Karpenter 노드 1대·큐 비움. 부하 테스트 후 재채점 시 2분 대기.
  2026-08-01 정정으로 과제지 문구가 "채점 시 2분 대기"에서 "**2분 내에 scale in/out 완료**"로 바뀌었다 — 대기 시간이 아니라 우리 쪽 목표치다.
- **치환 리터럴 범위**: `${...}` 플레이스홀더(cluster.yaml·k8s manifest)는 terraform output 으로 런북에서 치환 —
  k8s 는 `rendered/` 폴더로 전체 렌더링 후 디렉토리 apply.
  cluster_name 변경 시 cluster.yaml·10-karpenter-nodepool.yaml(NodeClass role/태그 셀렉터)·20-deployment.yaml(nodeSelector 값은 nodepool 이름)·helm settings.clusterName 을 함께 바꿔야 한다.
- **치환 가드는 2단계 필요** (실측): envsubst 는 목록 명시 여부와 무관하게 **unset 변수를 빈 문자열로 치환**하고
  PS7 `.Replace()` 도 빈 값을 그대로 넣으므로, 사후 `grep '\${'` 만으로는 값 누락을 못 잡는다.
  → ① 치환 전 변수 비어있음 검사 + ② 치환 후 grep/Select-String (목록 외 신규 플레이스홀더 탐지용). 둘 다 런북에 포함.

### module-4 채점 커버리지 (mark4.sh ↔ 구현)
<!-- [x] apply 후 mark4.sh 통과 확인 / [~] plan 수준 검증만 / [ ] 미구현 -->
<!-- 2026-08-01 실채점 결과로 전 항목 확정 (4-5·4-6 은 mark4.sh 가 manual marking 만 출력 → 주석 블록 쿼리·육안으로 직접 확인) -->

- [x] 4-1-A Cluster/NG/Multi-AZ — 실채점: `o11y-cluster 1.35 ACTIVE` / `t3.medium 2 2 2` / zone 1a·1c 2종
- [x] 4-2-A ALB/TG — 실채점: ALB 2개 `active application internet-facing`, app-tg `healthy healthy`(pod 2) / grafana-tg `healthy`(pod 1)
- [x] 4-3-A 워크로드 이름 — 실채점: log-generator 2 / o11y-otel 2 2 / o11y-loki ClusterIP 3100 / o11y-grafana 1
- [x] 4-4-A App API — 실채점: `{"status":"ok"}` / `error` / `3` 정확 일치. `{"status":"ok"}` 뒤 빈 줄은 지급 app.py jsonify trailing newline + 스크립트 `; echo` 중복이라 전 선수 공통 (module-1 1-5-A 와 같은 현상)
- [x] 4-5-A 로그 파이프라인 — 실채점: mark4.sh 주석 블록 쿼리(`{k8s_namespace_name="o11y"} | json | level="ERROR"`)로 ERROR 라인 조회 확인. Loki OTLP 기본 인덱스 라벨 의존이 실환경에서 성립 → `limits_config.otlp_config` 명시 승격 불필요(결정 로그 3번 비용 미발생)
- [x] 4-6-A Grafana — 실채점: 3패널 표시·범례 plain text(ERROR/WARN/INFO)·Recent Logs 에 4-5 로그·Save&Test 성공 전부 확인. `| __error__=""` 가드 추가 후 재배포 기준(함정 절)

#### module-4 함정 (구현 중 발견)

- **최초 지급 Dockerfile 은 flask 미설치**: `python:3.12-slim` + `COPY app.py` 뿐인데 app.py 가 flask import (requirements.txt 도 미지급) → 그대로 빌드하면 ModuleNotFoundError CrashLoop. 2026-08-01 정정으로 `RUN pip install --no-cache-dir Flask==3.1.3` 이 지급본에 추가됐다 → `provided/module-4/Dockerfile-2026-08-01`·`app/Dockerfile`(동일 본문). CloudShell 빌드는 최초 지급본(`provided/module-4/Dockerfile`)이 아니라 이 정정본을 쓴다.
- **Loki/Grafana helm chart 는 grafana-community 로 이관**: 구 `grafana/loki`(6.x)·`grafana/grafana` repo 는 동결. `grafana-community/loki` 는 18.x 로 리넘버링, `deploymentMode: SingleBinary` 는 `Monolithic` 의 deprecated 별칭.
- **Loki chart 18.x 기본값 함정 5종** (전부 loki-values.yaml 에서 오버라이드): ① `singleBinary.replicas` 기본 0 — 아무것도 안 뜸 ② `auth_enabled` 기본 true — 무인증 push/query 401 ③ `storage.type` 기본 s3 — 버킷 없이 기동 실패 ④ `schemaConfig` 기본 빈 값 — 기동 실패 ⑤ chunksCache 기본 memcached requests/limits 9830Mi(`allocatedMemory` 8192MB × 1.2, resultsCache 는 1229Mi) — t3.medium 스케줄 불가. 캐시를 살려야 하면 `resources` 오버라이드가 아니라 `chunksCache.allocatedMemory` 를 낮춘다. 추가: backend/read/write 기본 replicas 가 0이 아니라 Monolithic 과 공존 검증 에러 — 명시적 0 필요 (helm template 실렌더에서 발견).
- **OTel 공식 chart 는 DaemonSet 이름에 `-agent` 접미사 강제**: fullnameOverride 로도 `o11y-otel` 정확 일치 불가 → raw manifest (결정 로그 참조).
- **EKS 1.30+ 는 기본 StorageClass 없음**: gp2 SC 는 존재하나 default annotation 이 없어 storageClass 미지정 PVC 는 Pending → `o11y-gp3` SC 명시 생성 + values 에서 이름 참조.
- **StorageClass 는 helm 보다 먼저** (실배포에서 발견): `05-storageclass.yaml` 을 7단계에서 apply 하면 6단계 Loki `--wait` 가 PVC Pending(`storageclass ... "o11y-gp3" not found`)으로 영구 대기. 화면은 `Release "o11y-loki" does not exist. Installing it now.` 에서 멈춘 것처럼 보이지만 이건 설치 시작 안내지 에러가 아니다 — 리소스는 이미 생성됐고 `--wait` 가 pod Ready 를 기다리는 중. → 5단계에서 `00-namespace` 와 함께 apply. 중단 시 release 가 `pending-install` 로 잠기므로 `helm uninstall o11y-loki -n monitoring` + `kubectl delete pvc -n monitoring --all` 후 재시도 (module-3 Karpenter 와 동일 패턴).
- **치환과 적용을 한 코드 블록에 두지 않는다**: ① 값 확인 ② 치환 ③ 치환 확인 ④ 적용 을 4블록으로 분리. 한 덩어리면 붙여넣기 한 번에 `eksctl create cluster`·`kubectl apply` 까지 나가 렌더 결과를 볼 기회가 없고 실패 지점도 불분명하다. 2·5단계 모두 적용, 다른 모듈 런북도 같은 규칙.
- **mark.md 4-0 의 `source kubectl-connect o11y-cluster`**: 채점자 측 헬퍼로 추정 — mark4.sh 는 자체적으로 `aws eks update-kubeconfig` 수행(작업 규칙 4: 스크립트가 기준). 대응은 CloudShell 에서 update-kubeconfig 가 되도록 access entry fallback(런북 9단계)뿐.
- **LogQL `| json` 뒤에 `| __error__=""` 가드 필수** (실배포에서 발견): 지급 app.py 가 werkzeug 액세스 로그(stderr, 평문)를 억제하지 않아 `o11y` 스트림은 JSON + 평문 혼합이다. JSON 은 `/log` 호출 시에만 나오는데 평문은 ALB health check(30s)+readinessProbe(10s)로 상시 다수. 가드 없이 `| json` 만 쓰면 평문 라인에 `__error__=JSONParserErr` 가 붙은 채 드롭되지 않아 → Recent Logs 는 빨간 `JSON Parse Err` 배지 + 액세스 로그 노출, `sum by (level)` 두 패널은 level 라벨을 가진 라인이 0건이라 **No Data**(채점 4-6-A 감점 항목). 세 패널 모두 `| json | __error__=""` 로 수정. `level=~"..."` 같은 일반 라벨 필터가 아니라 `__error__` 필터를 써야 한다 — 에러 라인은 뒤따르는 라벨 필터를 건너뛸 수 있고 `__error__` 필터만 항상 적용된다. 수집기에서 stderr 를 드롭하지 않는 이유: 채점 4-5-A 쿼리 `| json | level="ERROR"` 는 에러 라인의 level 이 비어 있어 이미 걸러지므로 얻는 게 없고, 로그 유실 + 과제지 "/var/log/pods 수집" 문구와 충돌한다.
- **레벨 색은 Grafana 로그레벨 팔레트 hex 로 고정한다**: 색을 안 정하면 시리즈 등장 **순서**대로 배정돼 과제지 이미지와 어긋나고 구간에 한 레벨이 없으면 밀린다. `red`/`yellow`/`green` 같은 이름 색은 채도가 높아 이미지와 다르다 → Grafana 가 logs 패널 레벨 색으로 쓰는 classic 값 그대로 `#E24D42`(error)·`#EAB839`(warn)·`#7EB26D`(info) 를 `byRegexp /^error$/i` 등으로 고정. 세 패널 색이 서로 일치한다(Recent Logs 는 logs 패널이 detected_level 로 자동 색칠).
- **Recent Logs 는 파서가 아니라 라인 필터**: `{k8s_namespace_name="o11y"} |= "log generated"`. 과제지 이미지 판독 근거 두 개가 동시에 걸린다 — ① 라벨 컬럼이 `k8s_pod_name·k8s_pod_uid·log_file_path·observed_timestamp·time` 5개(알파벳순)뿐이고 `level`·`msg`·`req_id`·`ts` 가 없다 → `| json` 을 쓰지 않았다(파서가 뽑은 라벨은 이 컬럼에 나온다) ② 그런데 보이는 행은 전부 `log generated` JSON 이고 werkzeug 액세스 로그가 없다 → 그냥 셀렉터만 쓴 것도 아니다. 라인 필터는 라벨을 추가하지 않으므로 둘 다 만족하는 유일한 형태. 파서가 없으니 `JSON Parse Err` 도 원천 차단되고, 레벨 색은 Loki `discover_log_levels` 의 detected_level 로 나온다. **`"log generated"` 는 지급 app.py 의 msg 리터럴** — 30% 변동으로 msg 가 바뀌면 이 필터도 같이 고친다. 메트릭 두 패널도 같은 이유(이미지에서 막대가 `/log` 시점에만·범례 3개)로 액세스 로그를 제외한다(`| json | __error__=""`).
- **logs 패널 `showLabels: true`**: 이미지의 시간 옆 라벨 컬럼이 이것. 기본 false 라 안 켜면 이미지와 다르게 보인다.
- **파이 패널에 Loki instant 쿼리를 쓰면 `Value #A` 한 조각으로 뜬다** (실배포에서 발견): instant 는 table 형태 프레임(Time·level·Value)으로 와서 piechart 가 문자열 라벨을 조각 이름으로 못 쓴다. → **range 쿼리 + `reduceOptions.calcs: ["sum"]`**. 시리즈별 프레임이 legendFormat 이름으로 오므로 조각 이름이 plain text `ERROR`/`WARN`/`INFO` (채점 4-6-A 범례 항목). step == 버킷 폭이라 `count_over_time([$__auto])` 를 sum 하면 총건수와 일치. 범례는 이미지대로 **하단**·이름만(`values: []`), 조각 위 라벨 없음(`displayLabels: []`).
- **bars 로 그려도 점+선처럼 보인다**: `$__auto` 가 패널 폭 기준이라 버킷이 ~10초로 잘게 쪼개져 막대가 실선 두께가 되고, `showPoints` 기본 auto 가 그 위에 점을 찍는다. → 패널 `interval: "1m"` (최소 간격) + `showPoints: "never"`. drawStyle 문제가 아니다.
- **대시보드는 `/log` 호출이 선행돼야 데이터가 있다**: 앱은 요청 없이 JSON 로그를 만들지 않는다. 기본 구간 `now-1h` 안에 `/log` 호출이 없으면 수정 후에도 세 패널이 정당하게 No Data — 육안 채점 직전에 런북 8단계 `curl /log` 를 먼저 친다.
- **Grafana 비밀번호 `GoodJob!Skills<n>^^` 의 특수문자**: PS7 은 큰따옴표 안 `!`·`^^` 리터럴 처리라 안전, bash 는 `!` 히스토리 확장 위험 — linux 런북은 작은따옴표 조각 연결로 처리.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거. -->

- module-1 apply: ~2분 30초 (1차 실패 apply + 재apply 포함, log group 수동 삭제 시간 제외)
- module-2 apply: ~4분 (distribution 배포 대기가 대부분)
- module-3 apply:
- module-4 apply:
- 공통 병목: EC2 user-data pip 설치(~1-2분)가 healthcheck 가능 시점을 늦춘다

---
## 정정 로그
<!-- 과제지·채점지의 오류로 구현을 바꿨으면 질의일·답변일·출처와 함께 적는다. task.pdf·mark.pdf·provided/ 원본은 고치지 않는다. -->

### 2026-08-01 답변 (질의일 2026-07-31, 출처: `set-07/2026-08-01.txt` + `set-07/task-2/2과제.txt`)

원본 파일(`task.md`·`mark.md`·`mark/mark3.sh`·`provided/module-4/Dockerfile`)은 전부 그대로 두고,
내용이 바뀐 실행 파일만 **날짜 접미사 사본**으로 추가했다 (`mark/mark3-2026-08-01.sh`, `provided/module-4/Dockerfile-2026-08-01`).
원본과 정정본을 나란히 두면 대회 당일 또 정정이 와도 어느 답변에서 온 사본인지 파일명으로 구분된다.

| # | 정정 내용 | 구현 영향 |
|---|-----------|-----------|
| 공통 1 | 채점지 Timestamp 는 UTC 표기지만 채점은 KST 기준 (채점 시 유의사항 17번) | **없음** — task-2 채점 항목에 timestamp 값 비교가 없다. module-4 노드 TZ 는 이미 KST(`eksctl/cluster.yaml` preBootstrapCommands, 과제지 4-1 요구), 앱 `ts` 는 지급 app.py 가 UTC 고정이라 손댈 수 없고, Grafana 대시보드는 `timezone` 미지정 = browser 기본이라 채점자 브라우저에서 KST 로 보인다 |
| M2-1 | 과제지 5번 "Distribution Name" → "Distribution Comment" | **없음** — 표기 정정일 뿐. 구현은 처음부터 `comment = var.distribution_name`(cloudfront.tf)이고 mark2.sh 도 `.Comment` 로 distribution 을 찾는다. 변수명 개명은 tfvars 까지 파급되고 채점 이득이 0이라 하지 않음 |
| M3-1 | "Scale in/out 채점 시 2분 대기" → "**Pod/Node level Scale in/out 모두 2분 내**로 이루어져야 함" | **있음** — 기준이 "채점 스크립트 150초 창"에서 "2분"으로 좁아졌다. ScaledObject `scaleDown.stabilizationWindowSeconds` 15 → 0 (결정 로그 참조) |
| M3-2 | 3-3-A `57m`·`.5-eks-3385e9b`, 3-5-A `-8c66dbc4-r4fnp` 는 파란 글씨 = 채점 시 무시 | **없음** — 노드 가동시간·EKS patch version·pod 해시라 구현이 정하는 값이 아니다. 클러스터 version `1.35` 는 그대로 유지 |
| M3-3 | 채점 스크립트 3-6-A `seq 1 24` → `seq 1 30` (scale-out 대기 30초 연장, Nitro 부팅 시간 반영) | **없음**(완화 방향) — 자가채점만 정정본 `mark/mark3-2026-08-01.sh` 사용. `mark.md` 3-6-B 블록은 PDF 전사본이라 24 그대로 둔다 |
| M4-1 | 지급 Dockerfile 3행(`WORKDIR /app` 다음)에 `RUN pip install --no-cache-dir Flask==3.1.3` 삽입 | **있음** — 우리 우회본과 사실상 같은 조치가 공식화됐다. `provided/module-4/Dockerfile-2026-08-01` 추가, `app/Dockerfile` 을 정정본과 동일 본문(설치 줄을 COPY 앞으로, 버전 핀)으로 맞춤 |

---
## 결정 로그
<!-- append만. 절대 수정하지 않는다. 최신이 위로. 모듈 태그를 앞에 붙인다. -->

### 2026-08-04 [module-3] scale-in 목표를 "채점 창 150초" → "2분"으로, scaleDown 안정화 15초 → 0
- 맥락: 2026-08-01 정정으로 과제지가 "Pod/Node scale in/out 모두 2분 내"를 명시. 기존 설계는 안정화 15초 + consolidateAfter 60초로 노드 반환 ~140초 — 채점 스크립트 창(150초)엔 들어가도 과제지 기준은 초과, 여유도 10초뿐
- 채택: `stabilizationWindowSeconds: 0`. HPA 안정화 0 은 즉시 축소이고 축소 하한은 컨트롤러 sync 15초라 purge → ~15초 Pod 1 → consolidateAfter 60s → ~110초 노드 1 (문서 확인: k8s HPA 안정화 기본 300초·sync 15초 / KEDA min≥1 이면 cooldownPeriod·pollingInterval 무효, 1→N 은 HPA behavior 지배 / Karpenter 1.0 consolidateAfter 는 pod 제거 시점부터 카운트)
- 기각: consolidateAfter 단축 → 과제지가 60초 명시. terminationGracePeriodSeconds 단축 → 지급 app.py 에 SIGTERM 핸들러가 없어 기본 종료라 이미 빠름, 실측이 120초를 넘을 때만 꺼낼 카드
- 대가: 짧은 트래픽 골에도 즉시 축소 (채점용 워크로드라 무관). 실측값은 재배포 후 갱신 필요

### 2026-08-04 [module-4] Dockerfile 은 지급본 정정 반영본으로 (2026-07-31 "수정본" 결정의 사유 소멸)
- 맥락: 2026-08-01 정정이 지급 Dockerfile 3행에 `RUN pip install --no-cache-dir Flask==3.1.3` 을 넣는 것으로 공식화. 우리가 flask 미설치를 우회하려고 만든 `app/Dockerfile` 의 존재 이유가 공식 조치와 겹침
- 채택: `provided/module-4/Dockerfile-2026-08-01`(정정본 사본, 원본 유지) 추가 + `app/Dockerfile` 본문을 정정본과 동일하게(설치 줄을 COPY 앞 3행, 버전 핀). 런북 빌드 경로는 계속 app/ — 대회 당일 지급본이 또 다르면 수정 여지가 한 곳에 남는다
- 기각: app/Dockerfile 삭제 후 provided 직빌드 → 지급본 변형 시 손댈 곳이 provided/ 밖에 없어짐. provided/Dockerfile 원본 덮어쓰기 → provided/ 는 수령 원본이라는 규칙 위반
- 대가: 같은 내용 파일 2개 공존 (헤더 주석만 차이, 정정 로그에 관계 명시)

### 2026-07-31 [module-4] ALB·TG 는 Terraform 정확 이름 생성 + LBC TargetGroupBinding 으로 pod IP 등록
- 맥락: 채점 4-2 가 `describe-target-groups --names o11y-app-tg` 로 TG 이름을 정확 조회하고, app-tg healthy 2·grafana-tg healthy 1 (pod 수와 일치)을 요구
- 채택: Terraform 이 ALB 2·TG 2(target_type ip)·공유 SG·listener 를 정확한 이름으로 생성, LBC(chart 3.4.3) TargetGroupBinding 의 `targetGroupName` 참조로 pod IP 등록. `spec.networking.ingress` 의 소스 SG(${ALB_SG_ID})로 노드 SG 개방은 컨트롤러가 자동 관리 → k8s 플레이스홀더가 ${ECR_IMAGE} ${ALB_SG_ID} 2개로 끝남
- 기각: LBC Ingress 리소스로 ALB 자동 생성 → TG 이름이 `k8s-…` 랜덤이라 이름 채점 불가. instance/NodePort TG + ASG attach → 노드 단위 등록이라 healthy 수가 pod 수와 불일치(grafana 1 불가). TG ARN 플레이스홀더 → LBC v2.10+ 의 targetGroupName 참조로 불필요
- 대가: LBC 설치(helm)와 IRSA 정책(iam.tf vendored json) 관리 지점 추가 — 4-2 채점 구조상 대안 없음

### 2026-07-31 [module-4] OTel Collector 는 raw manifest (공식 helm chart 기각)
- 맥락: 채점 4-3 이 `kubectl get ds o11y-otel` 이름 정확 일치. 공식 opentelemetry-collector chart(0.165.0)는 daemonset 템플릿이 `<fullname>-agent` 접미사를 하드코딩 — fullnameOverride: o11y-otel 로도 `o11y-otel-agent` 가 됨
- 채택: SA+RBAC+ConfigMap+DaemonSet 단일 파일(20-otel-collector.yaml) raw manifest. 설정은 chart 의 logsCollection·kubernetesAttributes preset(_config.tpl)을 복제 — filelog `container` parser 로 body 가 앱 원본 JSON 유지(4-5 `| json` 전제), 이미지는 contrib 0.156.0 핀
- 기각: chart + 후처리 rename → helm 관리 이점 상실보다 못한 편법. Fluent Bit 등 대체 수집기 → 과제지가 OTel Collector·filelog·k8sattributes 를 명시
- 대가: chart 업데이트 추종 없음 — 수집 설정 변경 시 ConfigMap 직접 수정 (대회 범위에선 무관)

### 2026-07-31 [module-4] Loki 는 grafana-community chart 18.x Monolithic + filesystem/PV
- 맥락: 과제지 "Single Binary 모드, Chunks·Index 는 PV, OTLP ingestion". 구 grafana repo 는 동결·grafana-community 로 이관됨(실측: index.yaml 로 18.7.1 확인). 채점 4-5 LogQL 이 `{k8s_namespace_name="o11y"}` 라벨 필터 사용
- 채택: release 명 o11y-loki(→ svc 이름·3100 이 채점 4-3 일치, helm template 실렌더로 확인) + 기본값 함정 오버라이드(함정 절 참조) + `storage.type: filesystem` + singleBinary.persistence(o11y-gp3). OTLP 라벨은 Loki 3.x 기본 인덱스 라벨(k8s.namespace.name/k8s.pod.name 포함)에 의존 — otlp_config 불요
- 기각: S3 object storage → 과제지가 PV 를 명시. gateway/캐시 활성 → 채점 무관 + t3.medium 용량 초과. raw manifest → schemaConfig·ring 등 자체 작성 비용이 chart 함정 대응보다 큼
- 대가: Loki 차기 버전이 기본 인덱스 라벨을 줄이면 `limits_config.otlp_config` 추가 필요 (NOTES 함정 절 기록)

### 2026-07-31 [module-4] 지급 Dockerfile 대신 app/Dockerfile 수정본으로 빌드
- 맥락: 지급 Dockerfile 은 flask 를 설치하지 않는데 app.py 가 flask import (requirements.txt 미지급) — 그대로 빌드하면 CrashLoop. provided/ 는 수정 금지
- 채택: `app/Dockerfile` 수정본(RUN pip install flask 추가) 커밋, CloudShell 빌드에 이것 사용. app.py 는 지급 원본 그대로
- 기각: provided/ 직접 수정 → 저장소 규칙 위반. 런북에서 즉석 sed 수정 → 대회 당일 실수 지점만 추가
- 대가: 지급본과 수정본 Dockerfile 이 공존 — 런북·NOTES 에 수정본 사용을 명시해 혼동 방지

### 2026-07-31 [module-4] kubeconfig 격리를 3과제(task-3)까지 포함한 대회 전역 규칙으로 확장
- 맥락: module-3 결정(모듈별 kubeconfig + 터미널별 KUBECONFIG)은 module-3·4 2클러스터 전제였으나, 당일 3과제(task-3, EKS Auto Mode·apne2)도 EKS 를 사용 — 대회 중 동시 운용 클러스터가 최대 3개
- 채택: 동일 패턴을 module-4 런북에도 적용하고 "터미널 1개 = 클러스터 1개"를 과제 불문 전역 규칙으로 명문화 (README 서두). task-3 런북도 자체 KUBECONFIG 고정을 이미 사용
- 기각: 공유 ~/.kube/config + context 전환 → 클러스터 3개에서 전환 실수 확률만 증가
- 대가: 없음 (기존 결정의 적용 범위 확대)

### 2026-07-31 [module-3] 2클러스터 운용: 모듈별 kubeconfig 파일 + 터미널별 KUBECONFIG 고정
- 맥락: module-3(apne2)·module-4(apne1)에 클러스터가 각각 있음. 공유 ~/.kube/config 는 current-context 가 "마지막에 만든 클러스터"를 향해, 전환을 잊으면 kubectl·helm 이 조용히 엉뚱한 클러스터로 감
- 채택: 모듈 디렉토리에 kubeconfig(gitignored) + 모듈 전용 터미널 첫 줄 `$env:KUBECONFIG` 고정 — 터미널 1개 = 클러스터 1개. eksctl 이 생성 시 KUBECONFIG 경로에 써 주고, 재부팅 복구는 `aws eks update-kubeconfig --kubeconfig <경로>` 한 줄
- 기각: `use-context` 전환 — 휴먼 에러 잔존. 별칭/프롬프트 표시 — 표시는 사고를 알려줄 뿐 막지 못함
- 대가: 터미널 탭을 모듈별로 유지해야 함 (대회에서 어차피 모듈별 병렬 작업이라 부담 없음)

### 2026-07-26 [module-3] Karpenter 는 --set replicas=1 (chart 기본 2는 노드 1대에서 helm --wait 행)
- 맥락: 실배포에서 helm --wait 가 무한 대기. chart 기본 replicas 2 + required podAntiAffinity(hostname) + 자기 nodepool 노드 배제 nodeAffinity — addon NG 는 채점 고정 1/1/1 이라 두 번째 replica 가 앉을 노드가 구조적으로 없음
- 채택: `--set replicas=1` — 채점 3-5 는 pod 존재만 확인, 대회 스택에 컨트롤러 HA 불필요
- 기각: addon NG 노드 증설 → 채점 3-2 가 `1 1 1` 정확 일치라 위반. anti-affinity 를 preferred 로 완화 → helm 값 구조가 깊어 관리 지점만 증가
- 대가: 컨트롤러 단일 장애점 — addon 노드 재시작 시 스케일링 일시 중단 (채점 시간 내 무관)

### 2026-07-26 [module-3] scale-in 150초 창 대응: ScaledObject 에 HPA scaleDown behavior 오버라이드
- 맥락: 채점 3-7 이 purge 후 150초 내 Pod 1·노드 1 을 요구. HPA 기본 scale-down 안정화가 300초라 기본값으로는 구조적으로 불가
- 채택: `advanced.horizontalPodAutoscalerConfig.behavior.scaleDown {stabilizationWindowSeconds: 15, Percent 100/15s}` → purge 감지(HPA sync ~15초) 후 ~35초에 Pod 1, consolidateAfter 60s 후 ~140초에 노드 1
- 기각: 기본값 유지 → 300초 안정화만으로 실패 확정. consolidateAfter 단축 → 과제지가 60초로 명시(변경 불가)
- 대가: 짧은 트래픽 골에도 즉시 축소됨 — 채점용 워크로드라 무관

### 2026-07-31 [module-3] pollingInterval 삭제 (KEDA webhook 경고, minReplicaCount≥1 에서 무효)
- 맥락: apply 시 KEDA 2.20 webhook 경고 "PollingInterval is configured but is not relevant". pollingInterval 은 operator 의 트리거 직접 폴링 주기로 0↔1 활성화(min=0/idleReplicaCount=0) 또는 useCachedMetrics 에만 적용 — min=1 이면 1→N 은 전부 HPA 자체 폴링(~15초)이라 완전 무효
- 채택: `pollingInterval: 5` 삭제. 위 150초 창 결정의 "≤5초 감지" 근거는 오류였고, 실제 감지 하한은 HPA sync ~15초 (실측 ~35초 Pod 1 은 그대로 유효). 채점 3-4 는 min/max/trigger type/queueLength 4개 필드만 검사해 무관
- 기각: min=0 전환으로 경고 해소 → 과제지가 "메시지 없으면 Pod 1개" + min=1 명시라 위반
- 대가: 없음. 대회 변동으로 min=0 이 되면 pollingInterval 재도입 필요

### 2026-07-26 [module-3] 노드 Name 태그는 eksctl `instanceName` 필드로 (set-05 tags 패턴 폐기)
- 맥락: 채점 3-2 가 EC2 인스턴스의 `tag:Name=skm-cluster-addon-ng-node` 를 검사. EKS MNG `tags` 는 NG 리소스에만 붙고 인스턴스에 전파되지 않음(EKS API 문서 + eksctl 소스 확인) — set-05 의 `tags: {Name}` 은 미채점이라 안 들켰을 뿐 무효
- 채택: `instanceName: skm-cluster-addon-ng-node` (eksctl 이 launch template TagSpecifications 로 인스턴스 Name 태그 생성)
- 기각: `tags: {Name: ...}` → 인스턴스 미전파로 채점 실패. launchTemplate 직접 관리 → eksctl 관리 이점 상실
- 대가: 없음

### 2026-07-26 [module-3] addon NG taint 는 CriticalAddonsOnly=true:NoSchedule
- 맥락: 과제지 "taint 로 Addon NG 에서 App 실행 차단" + 시스템 워크로드(CoreDNS·KEDA·Karpenter)는 그 NG 에서 돌아야 함. MCP/공식 문서 확인: CoreDNS EKS addon 기본 toleration 과 Karpenter chart 기본 toleration 에 `CriticalAddonsOnly Exists` 가 이미 포함
- 채택: `CriticalAddonsOnly=true:NoSchedule` — CoreDNS·Karpenter 무설정 스케줄, KEDA 만 helm `tolerations` 값 1개 추가, vpc-cni/kube-proxy 는 DaemonSet 이라 무관
- 기각: 커스텀 키(예: addon=true) → CoreDNS addon 에 toleration 설정 주입 + 컴포넌트별 helm 값 필요, 관리 지점만 증가
- 대가: 없음

### 2026-07-26 [module-3] 퍼블릭 엔드포인트 + bastion 제거 (set-05 구조 폐기)
- 맥락: 채점(mark3.sh)이 일반 CloudShell 에서 kubectl 실행 — private 엔드포인트면 VPC 밖 CloudShell 이 접근 불가. set-05 는 private+bastion 이었으나 그 세트 요구사항이었을 뿐
- 채택: `clusterEndpoints {publicAccess: true, privateAccess: true}`, 노드는 private 서브넷 + NAT. bastion 리소스 전부 삭제. `authenticationMode: API_AND_CONFIG_MAP` + access entry fallback 을 런북에 포함
- 기각: private 엔드포인트 + bastion → 채점 경로가 CloudShell 이라 불가. 과제 미요구 리소스에 비용·시간 추가
- 대가: API 엔드포인트 인터넷 노출 (EKS 인증으로 보호, 과제지 보안 요구 없음)

### 2026-07-26 [module-3] IRSA 통일 (Pod Identity 기각), interruption queue 생략
- 맥락: Karpenter 공식 getting-started 는 Pod Identity + interruption queue 를 설치. KEDA·앱·Karpenter 세 주체가 AWS 권한 필요
- 채택: eksctl withOIDC IRSA 로 3개 SA(keda-operator/keda, karpenter/kube-system, order-processor/skillsmkt) 사전 생성, helm 은 SA 재사용. interruptionQueue="" (미채점 선택 기능, 컨트롤러 정책에 SQS 권한 불필요)
- 기각: Pod Identity → pod-identity-agent addon 추가 필요, set-05 검증 이력 없음. 두 메커니즘 혼용 → 디버깅 지점 증가
- 대가: `identityOwner: operator` 는 KEDA 3.0 에서 제거 예정(deprecated) — 2.20.1 에선 정상, 차기 세트에서 TriggerAuthentication 전환 검토

### 2026-07-26 [module-2] KVS 키는 keys_exclusive 단일 리소스로 관리
- 맥락: 채점 2-2 가 `list-keys` 결과를 정확 일치로 검사 — 여분 키가 하나라도 있으면 실점. terraform MCP 로 6.56 문서 확인
- 채택: `aws_cloudfrontkeyvaluestore_keys_exclusive` (키 3개 선언, 미선언 키 자동 제거 + KVS API 호출 최소화)
- 기각: `aws_cloudfrontkeyvaluestore_key` ×3 → 수동 추가된 여분 키를 못 지우고, 키당 개별 API 호출
- 대가: 이 리소스가 KVS 키 전체의 단독 소유자가 됨 — 수동 put-key 는 다음 apply 때 제거됨 (채점 2-6 은 스스로 0.3 복원하므로 무관)

### 2026-07-26 [module-2] "Pay-as-you-go 타입"은 no-op (기본값)
- 맥락: 과제지가 "Pay-as-you-go 타입" distribution 을 요구. aws-knowledge MCP 확인: flat-rate 플랜(2025-11 출시)은 콘솔 전용 opt-in 구독이고 Terraform/API/CFN 에 플랜 인자 자체가 없음
- 채택: 아무 설정 안 함 — Terraform 생성 distribution 은 구조적으로 PAYG. `price_class` 는 엣지 로케이션 범위 설정으로 플랜과 무관하므로 미설정(기본 PriceClass_All)
- 기각: `price_class` 등으로 "타입"을 표현 → 과금 모델과 무관한 인자
- 대가: 없음

### 2026-07-26 [module-2] Set-Cookie 는 response.cookies 객체로, 발급 여부는 assigned 헤더로 게이트
- 맥락: 채점 2-4 는 쿠키 재방문 시 Set-Cookie 부재를, 2-5 는 첫 방문 시 `Path=/; Max-Age=86400` 발급을 정확 검사. aws-knowledge MCP 확인: CloudFront Functions 이벤트에서 Set-Cookie 헤더는 `response.headers` 가 아니라 `response.cookies` 로만 다룸
- 채택: req-fn 은 신규 배정시에만 `x-sp-ab-assigned` 요청 헤더를 세우고, res-fn 은 그 헤더가 있을 때만 `response.cookies['x-sp-ab']` 설정 (과제지 명세 그대로)
- 기각: `response.headers['set-cookie']` 직접 설정 → 문서상 cookies 객체 밖의 Set-Cookie 는 이벤트에 반영 안 됨. res-fn 이 request.cookies 부재로 판단 → 배정 버전(a/b)을 알 수 없어 uri 재파싱 필요
- 대가: viewer-request 가 세운 헤더가 viewer-response 의 event.request 에 보인다는 명시 문서 없음(AWS 공식 A/B 패턴이라 실동작은 검증됨) — apply 후 런북 2단계 curl 로 실측

### 2026-07-26 [module-2] 함수 JS 는 정적 파일 (templatefile 미사용)
- 맥락: 30% 변동 규칙상 리터럴은 변수화 대상이지만, JS 안의 쿠키·헤더·KVS 키명까지 변수화하려면 templatefile 필요
- 채택: 정적 `cloudfront/*.js` + NOTES 함정 절에 치환 범위 기록
- 기각: `templatefile()` 로 JS 템플릿화 → `${}` 이스케이프 관리 비용이 리터럴 4종 직접 수정보다 큼
- 대가: 쿠키명 변경 시 변수(`ab_cookie_name`)와 JS 2개 파일을 같이 고쳐야 함

### 2026-07-26 [module-1] mark.md의 기대 출력이 원본 pdf와 다른 오류를 해결
- 맥락: 기존 mark.md 1-6-A 기대 출력이 불일치하다는 문제를 확인했지만, 이는 원본 pdf에서 변환 도중 오류가 발생해 마지막 출력이 2번 작성된것임을 확인
- 채택: 수동으로 mark.md의 기대 출력을 원본 pdf와 동일하게 수정
- 기각: X
- 대가: X

### 2026-07-26 [module-1] default VPC → 자체 VPC로 전환 (아래 default VPC 결정 번복)
- 맥락: 대회 당일 30% 변동으로 "VPC 이름/CIDR 지정"이 나오면 data source 기반 default VPC는 변수화 불가 — retrofit 시 리소스 5개 신규 + 서브넷 교체로 인스턴스 재생성 (사용자 지적)
- 채택: 자체 VPC + public 서브넷 + IGW + 라우팅 (이름·CIDR은 vpc_name/vpc_cidr/subnet_cidr 변수)
- 기각: default VPC 유지 → 30% 규칙(이름·CIDR 변수화)과 구조적으로 충돌. create_vpc 토글 변수 → 안 쓰는 분기(죽은 유연성)
- 대가: 리소스 +5 (전부 무료), apply +30초

### 2026-07-26 [module-1] GSI를 key_schema 블록으로 선언
- 맥락: AWS provider 6.x에서 GSI `hash_key`/`range_key` 인자가 deprecated (terraform MCP로 6.56 문서 확인)
- 채택: `global_secondary_index` 내 `key_schema` 블록 (HASH user_id / RANGE reserved_at)
- 기각: 기존 세트처럼 `hash_key`/`range_key` 인자 → deprecation 경고, 향후 major에서 제거 예정
- 대가: 없음 (동일 결과)

### 2026-07-26 [module-1] EC2는 default VPC에 배치
- 맥락: 과제지가 VPC를 요구하지 않고, 채점(1-4~1-6)은 Public IP :8080 접근만 검사
- 채택: `data.aws_vpc.default` + 첫 서브넷. 없으면 `aws ec2 create-default-vpc`로 복구(런북 0단계)
- 기각: 커스텀 VPC(+서브넷·IGW·라우팅 ~6리소스) → 채점 무관 리소스
- 대가: 로컬 계정에 default VPC가 없어서 plan이 한 번 실패, create-default-vpc로 해결 (~1분)

### 2026-07-26 [module-1] Lambda handler는 lambda.handler (지급 파일명 그대로)
- 맥락: 지급 `lambda.py` 무수정 사용 조건. 파일명이 python 예약어와 같음
- 채택: `archive_file` source_file로 원본 zip, handler `lambda.handler` — 런타임은 importlib 로드라 모듈명 lambda 무관
- 기각: archive_file `source` 블록으로 zip 내부 파일명을 index.py로 개명 → 불필요한 우회
- 대가: 없음

### 2026-07-26 [module-1] app.py는 user-data base64 임베드로 배포
- 맥락: module-1은 Dockerfile 미지급 = EC2 직접 실행 전제. app.py+requirements 합계 ~7KB로 user-data 16KB 한도 내
- 채택: set-05 module-2에서 검증된 base64 heredoc + systemd(Restart=always) 패턴 재사용
- 기각: S3 업로드 + 인스턴스에서 다운로드 → 버킷·GetObject IAM·순서 의존만 늘고 이득 없음
- 대가: app.py 내용 변경 시 인스턴스 재생성(user_data 변경) 필요
