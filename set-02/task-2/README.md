# set-02 / task-2

제2과제는 **독립 모듈 3개**로 구성된다. 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다. 배포 순서는 자유이고 병렬 배포도 된다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-workflow](module-1-workflow/) | 성적 처리 서버리스 워크플로우 | ap-southeast-1 | S3 + Lambda + Step Functions + DynamoDB | CloudShell |
| [module-2-analytics](module-2-analytics/) | 실시간 주문 로그 분석 | ap-northeast-2 | VPC + EC2 + ALB + Kinesis + Managed Flink Studio | CloudShell + Zeppelin 수동 시연 |
| [module-3-msk](module-3-msk/) | MSK 센서 스트리밍 | ap-northeast-1 | VPC + MSK + EC2 + Lambda + DynamoDB + S3 | CloudShell |

> 구 3번 **Cloud Event Handling 은 RC 판(2026-08-23)에서 삭제**됐고 MSK 가 3번이 됐다.
> 저장소도 `module-3-event/` 를 지우고 `module-4-msk/` 를 `module-3-msk/` 로 옮겼다 —
> 되살릴 일이 생기면 git 이력에서 꺼낸다 ([NOTES.md](NOTES.md) 정정 로그).

> **대회 당일에는 [DAY-OF.md](../../DAY-OF.md) 를 먼저 연다.** 과제지는 종이로 배부되어 파일 대조가 안 되므로,
> DAY-OF 8절 값 대조표로 종이 과제지를 훑고 다른 값에 형광펜을 친 뒤 이 런북으로 들어온다.

## 값 대조표

> [DAY-OF.md 8절 값 대조표](../../DAY-OF.md#10-값-대조표) 로 이동했다.

## 배포 순서 — 오래 걸리는 것부터, 터미널 병렬

모듈은 서로 의존하지 않는다. **PowerShell 터미널 3개를 열어 모듈별로 하나씩 붙이고, apply 가 오래 걸리는 순서로 착수한다.** module-3(MSK) 을 먼저 걸어두고 그 30여 분 동안 나머지 둘을 끝내는 게 전체 소요를 지배한다. 순차로 돌리면 합이 45분을 넘지만, 병렬이면 module-3 의 35분이 곧 총 소요다.

| 착수 | 모듈 | apply 소요 | 병목 | 추가 대기 |
|---|---|---|---|---|
| 1번째 | [module-3-msk](module-3-msk/) | **35분** (실측 2026-08-16) | MSK 클러스터 하나가 31분 40초 | 없음 — apply 끝나면 파이프라인이 이미 흐른다 |
| 2번째 | [module-2-analytics](module-2-analytics/) | 8~12분 (추정) | Studio 노트북 CFN 스택, ALB | EC2 user_data pip + TG 헬스체크 2~3분 |
| 3번째 | [module-1-workflow](module-1-workflow/) | 1~2분 (추정) | 없음 (전부 서버리스) | 없음 |

module-3(MSK) 만 실측이고 나머지는 리소스 구성 기준 추정이다. 실측하면 [NOTES.md](NOTES.md) 실측 소요시간 절에 채운다.

터미널 하나 = 모듈 하나로 고정한다(디렉터리를 오가다 엉뚱한 모듈에 apply 하는 사고를 원천 차단):

```powershell
cd module-<n>-<name>\terraform   # 이 터미널은 이후 이 모듈만 다룬다
```

## 공통 워크플로

본 PC 단계는 **PowerShell 7 기준**(대회 환경). 본 PC 가 Linux 면 각 모듈의 `README.linux.md` 를 사용한다.

**배포 전 각 모듈 `terraform/terraform.tfvars` 의 `player_number` 를 본인 등번호로 바꾼다.** apply 가 tfvars 를 자동으로 읽으므로 `-var` 를 붙이지 않는다.

```powershell
cd module-<n>-<name>\terraform
terraform init
terraform apply
terraform output -json > outputs.json
# 이후 모듈별 README 의 "배포 순서" 를 따른다.
```

공식 채점 스크립트는 `mark/`(mark2-1~3.sh)에 있다. 제공 배포파일 중 문서(`*.md`)만 `provided/`에 있고 **소스·데이터·바이너리는 저장소에 없다** — 시작 전에 배부물을 같은 이름으로 `provided/module<N>/` 에 놓는다(`.gitignore` 처리라 커밋되지 않는다):

```
provided/module1/  lambda-function.py  test.csv
provided/module2/  app.py  requirements.txt
provided/module3/  app          # RC 배부본 디렉터리 이름 (구판 zip 은 module4)
                                # (재번호되면 module-3-msk/terraform/terraform.tfvars 의 provided_dir 만 바꾼다)
```

`provided/` 는 수정하지 않으며 각 모듈 terraform 이 직접 참조하거나 복사본을 둔다.

```bash
# 채점 시 기본 리전 설정 (채점지 사전 작업)
aws configure set default.region ap-southeast-1   # module-1
aws configure set default.region ap-northeast-2   # module-2
aws configure set default.region ap-northeast-1   # module-3 (MSK)
```

채점 스크립트는 CloudShell 우상단 **Actions > Upload file** 로 `mark/mark2-N.sh` 를 올린 뒤 실행한다. `mark2-1.sh` 은 채점지 1-0 절차를 그대로 흉내내므로 `provided/module1/test.csv` 도 같은 방법으로 함께 올린다. Windows 에서 올린 스크립트는 CRLF 가 섞여 bash 가 깨지므로 실행 전 `sed -i 's/\r$//' <파일>` 로 정리한다.

## 공통 규칙

- 리소스 이름은 과제지에 명시된 값과 **정확히 일치**(이름 일치 채점 항목 다수). 과제지 원문에 오타가 있어도 그대로 따르되, **정본이 바뀌면 정본을 따른다**.
- 채점지(`mark/`)와 과제지(`task.md`)가 어긋나면 **채점 스크립트가 1순위**다. 수동 채점 여지가 있으면 합집합으로 만든다.
- 상태가 채점 대상인 모듈이 있다 — module-2 Flink 노트북은 시연 후 **READY** 로, module-3 alert 버킷은 `bin/app` 을 지운 상태로 둔다.
- **module-1 은 채점 직전에 버킷·테이블을 비워야 한다.** 데이터가 남아 있으면 채점자가 1-1·1-5·1-6 을 모두 오답 처리한다(과제지 1)·3)). test.csv 는 채점자가 올린다 — 선수가 올린 상태로 두지 않는다.
- PowerShell 7.3+ 는 네이티브 명령 인자의 따옴표를 그대로 전달한다 — JSON 인자는 작은따옴표로만 감싼다. PS 5.1 식 `\"` 이스케이프는 백슬래시가 그대로 들어가 JSON 파싱 오류. HTTP 확인은 `Invoke-RestMethod` 를 쓴다.

> 설계 근거·요구사항↔구현 매핑은 각 모듈 README 하단에, 결정·실측 기록은 [NOTES.md](NOTES.md) 에 있다.
