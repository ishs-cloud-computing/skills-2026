# 런북 실행 피드백 (실 apply 세션)

> 2026-08-02 실 배포·실채점 리허설 중 발견한 런북 개선점. 확정된 항목은 각 README/NOTES에 반영 후 여기서 `[반영]` 표시.

## 0단계 — IAM 프로브 [반영]

- `aws iam delete-role` 성공 시 아무 출력이 없어, 프로브가 "생성만 되고 삭제는 됐는지" 눈으로 확인이 안 된다. 성공 경로에도 한 줄 출력(`Write-Host "IAM OK"`)을 추가하면 판단이 빨라진다.

## 실행 순서 (루트 README) [반영]

- "터미널 4개를 동시에 연다"고만 되어 있고 **module-2·3 apply를 언제 시작할지**가 순서 5·6번(module-4/1 대기 후)으로 적혀 있다. 실제로는 module-2·3 apply가 서로·module-1/4와 완전 독립이라 4개를 처음에 전부 걸어두는 편이 총 대기 시간이 짧다. 검증·채점만 순서대로 하면 된다.
  - 근거: module-2/3은 apply 자체가 짧고(EC2·Lambda), 대기 병목은 module-1(DocumentDB ~15분)·module-4(EKS ~20분)뿐이다.

## 채점 스크립트 전송 경로 (가장 큰 실행 리스크) [반영]

- 런북은 "git clone 또는 Actions → Upload file"이라 적혀 있으나, 이 저장소는 **private**(익명 clone 404)이라 CloudShell에서 `git clone`이 바로 안 된다. 대회 당일 CloudShell에 GitHub 자격증명을 넣는 건 시간 낭비이므로 **업로드 경로를 기본으로 명시**하고, clone은 "public일 때만"이라는 단서를 붙여야 한다.
- 로컬(Windows Git Bash) 대체 실행도 불가: `jq`가 없다(mark 스크립트 의존). 채점은 사실상 CloudShell 전용이라는 점을 런북에 명시하는 게 안전하다.
- module-4는 로컬에 Docker가 없어 **이미지 build/push가 CloudShell 필수 경로**다. 즉 CloudShell 접속 실패 = module-4 전체 블로킹. 런북 0단계에 "CloudShell 접속 확인"을 선행 체크로 넣으면 늦게 발견하는 사고를 막는다.

## `.env` CRLF — 실제로 재현된 버그 (우선순위 높음) [반영]

- module-4 1단계의 `@"..."@ | Set-Content .env`로 만든 `.env`는 **마지막 줄에만 CRLF**가 붙는다(PowerShell이 파일 끝 개행을 CRLF로 씀). 실측:
  ```
  export ECR_IMAGE=600440344359.dkr.ecr.us-west-2.amazonaws.com/skills-sqs-worker:latest^M$
  ```
  CloudShell에서 `source .env` 하면 `ECR_IMAGE` 값 끝에 `\r`이 붙어 `docker build -t "$ECR_IMAGE"` / `docker push`가 잘못된 태그로 실패한다. 하필 마지막 줄이 build에 쓰이는 변수라 100% 터진다.
- 런북의 CRLF 가드는 **mark 스크립트에만** 걸려 있어 이 경로를 못 잡는다. 두 가지 중 하나를 런북에 반영해야 한다:
  - 생성 측: `.env` 작성 시 `[IO.File]::WriteAllText(".env", $body.Replace("`r`n","`n"))`
  - 사용 측: CloudShell 3단계 `source .env` 앞에 `sed -i 's/\r$//' .env` 추가 (mark 스크립트 가드와 동일 패턴이라 일관적)

## CloudShell 업로드 경로/작업 디렉터리 [반영]

- CloudShell "Actions → 파일 업로드"는 항상 `$HOME`(`/home/cloudshell-user`)에 **평평하게** 떨어진다. 런북에는 `bash mark/mark2-3.sh`처럼 `mark/` 하위 경로로 적혀 있어 그대로 치면 `No such file or directory`가 난다. 업로드 경로 기준 명령(`bash mark2-3.sh`)으로 고치거나, "업로드 후 `mkdir -p mark && mv mark2-*.sh mark/`" 한 줄을 넣어야 한다.
- CloudShell 홈은 **리전별로 분리**된다. module별 리전이 다르므로 mark 스크립트도 리전마다 다시 업로드해야 한다(ap-southeast-1에 올린 파일이 us-west-2에 없다). 런북에 이 점을 한 줄 명시.

## CloudShell 잔존 VPC 환경이 업로드를 막는다 (실측) [반영]

- ap-northeast-2 CloudShell을 열자 이전 세트에서 만든 VPC 환경 탭(`wsc2026-skills-vpc`)이 **활성 탭으로 복원**됐고, 그 환경은 `Invalid VPC configuration provided. The subnet ID 'subnet-...' does not exist`로 생성 실패 상태였다. 이 탭이 활성이면 작업 메뉴의 "파일 업로드/다운로드"가 **비활성**(`File transfer isn't available for VPC environments`)이라 mark 스크립트를 못 올린다.
- 대응: 기본 리전 탭(`ap-northeast-2`)을 눌러 전환하면 정상. 런북에 "CloudShell 진입 시 활성 탭이 VPC 환경이면 기본 탭으로 전환" 한 줄이 필요하다. 대회 당일에도 계정 재사용 시 같은 상황이 재현될 수 있다.

## module-4 7단계 access entry — policy ARN 오타 (확정 버그) [반영]

- README 7단계의 `--policy-arn arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`는 **잘못된 ARN**이다. 실행하면:
  ```
  An error occurred (ResourceNotFoundException) when calling the AssociateAccessPolicy operation: The specified policyArn could not be found.
  ```
- 정확한 값은 리전 세그먼트가 빈 `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy` (콜론 2개). `aws eks list-access-policies`로 확인함. README 수정 필요.
- 추가: 이번 환경의 CloudShell 자격증명은 `arn:aws:iam::600440344359:root`였다(콘솔 root 로그인). root ARN으로도 `create-access-entry`/`associate-access-policy`는 정상 동작했다. 다만 대회 계정은 root 미지급이므로 실제로는 IAM 유저 ARN이 나온다 — 런북 문구는 그대로 유효.

## module-4 5단계 — namespace 중복 apply 경고 [반영]

- `k8s/00-namespace.yaml`을 apply하면 다음 경고가 뜬다:
  ```
  Warning: resource namespaces/skills-sqs is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply.
  namespace/skills-sqs configured
  ```
  eksctl Fargate profile이 `skills-sqs` 네임스페이스를 먼저 만들기 때문이다(선언적 생성이 아님). 동작엔 문제없고 자동 패치되지만, 채점자가 화면을 볼 때 경고가 뜨는 게 신경 쓰이면 런북에 "정상 동작"이라고 한 줄 달아두는 편이 낫다.

## module-2 teardown — Lattice target group attachment 삭제 실패 (재실행으로 해결) [반영]

- `terraform destroy` 1회차가 다음으로 실패했다:
  ```
  Error: waiting for VPC Lattice Target Group Attachment (tg-.../i-.../8080) delete:
  unexpected state 'UNUSED', wanted target ''. last error: TargetGroupNotInUse
  ```
  EC2가 먼저 삭제돼 target이 `UNUSED`로 떨어졌는데 provider가 빈 상태만 기다려서 나는 레이스다. VPC·SG·Service는 이미 지워진 상태로 중단된다.
- 대응: `terraform destroy`를 한 번 더 실행하면 남은 attachment/target group이 정리된다. README teardown 절에 "1회 실패 시 재실행" 문구 추가 권장.

## module-4 teardown — `kubectl delete -f rendered/`가 멈춘다 [반영]

- 9단계 첫 명령 `kubectl delete -f rendered/`가 모든 리소스 삭제 메시지를 출력한 뒤에도 **프로세스가 종료되지 않고 15분 이상 매달렸다**(`skills-sqs` 네임스페이스는 이미 사라진 상태). 뒤따르는 `helm uninstall`이 아예 실행되지 않아 teardown 전체가 정지한다.
- 대응: 삭제 메시지가 다 나온 뒤에도 프롬프트가 안 돌아오면 kubectl을 끊고 다음 단계로 진행하면 된다. 런북에 `kubectl delete -f rendered/ --wait=false`를 쓰거나 "출력 후 안 끝나면 Ctrl+C" 문구를 넣는 게 낫다.
- 참고: 중단된 kubectl을 죽인 뒤 helm uninstall을 다시 돌리면 `Failed to purge the release: secrets "sh.helm.release.v1.keda.v1" not found` 경고가 뜬다(먼저 돌던 프로세스가 릴리스 시크릿을 이미 지움). 리소스는 정상 제거된 상태라 무시해도 된다.

## eksctl delete cluster 실측 [반영]

- 11:57:02 시작 → 12:04:45 `all cluster resources were deleted`. **약 8분** (생성 19분 대비 절반 이하).
- Fargate profile은 순차 삭제되며 프로필당 ~2분.

## 대기 시간 관리 [반영]

- eksctl create cluster는 20분 내외라 에이전트/도구의 명령 타임아웃(10분)을 넘긴다. 런북에 "별도 창에서 detach 실행 + 로그 파일로 진행 확인"을 권장 문구로 넣으면 재실행 사고를 줄인다.

## 실측 소요 시간 (2026-08-02 리허설, 4모듈 동시 진행) [반영]

| 단계 | 실측 |
|------|------|
| module-3 terraform apply | ~1분 (16 add) |
| module-2 terraform apply | ~2분 (24 add) |
| module-1 terraform apply | ~7분 (22 add, DocumentDB 인스턴스 병목) |
| module-4 terraform apply | ~3분 (30 add, NAT GW 병목) |
| module-4 eksctl create cluster | **19분** (11:00:08 시작 → 11:19:10 ready) |
| module-4 CloudShell docker build+push | ~2분 |
| helm karpenter + keda | ~2분 |
| module-1 user-data seed 완료까지 | apply 후 즉시 200 (health 대기 거의 없음) |
| module-3 실경로 복구 (CloudTrail→EventBridge→Lambda) | **19.6초** (런북 상정 "수 분"보다 훨씬 빠름) |
| module-4 scale out (12건 → pod 6 + 노드 2) | 60초 이내 |
| module-4 scale in (pod 0 + 노드 0) | 큐 소진 후 ~3분 |

- 런북의 "module-1 배포 ~15분"은 과대 추정(실측 7분), "module-4 eksctl ~20분"은 정확했다.

## 채점 스크립트 실행 시간 — mark2-4가 11분 [반영]

- `mark2-4.sh`는 CloudShell에 kubectl이 없어 설치부터 하고, 4-6에서 `sleep 60`×3을 돈다. 실측 **약 11분**(02:22→02:33). mark2-1/2/3은 각 1~3분.
- 채점 시간 배분 시 module-4만 별도로 10분 이상을 잡아야 한다. 런북 8단계 밑에 예상 소요를 적어두면 좋다.
- 4-5/4-6 판정 우려는 실측으로 해소 확인: 4-5 시점엔 min 0이라 Worker Pod가 없지만, 4-6에서 `sent=12` → 60초 시점에 pod 6개가 Karpenter `t3.medium` 노드 2대(`skills-sqs-nodepool-*` NodeClaim)에 배치된 출력이 남는다. 공식 판정 기준대로 4-6 출력으로 4-5를 커버할 수 있다.

## module-1..3 vs module-4 명령 형식 불일치 [보류]

- module-1·2·3 README는 `terraform -chdir=terraform apply`, module-4는 `cd terraform; terraform apply`. 두 형식이 섞이면 `cd` 상태에 따라 잘못된 디렉터리에서 실행할 위험이 있다. 한쪽으로 통일 권장(module-4는 output 로드에 `cd`가 필요하므로 `cd` 형식으로 통일이 자연스럽다).
- 보류 사유: 이번 리허설에서 실제 사고로 이어지지 않았고, 검증된 런북 명령을 광범위하게 바꾸는 변경이라 리스크 대비 이득이 작다. 다음 세트 런북 작성 시 처음부터 통일하는 쪽으로 가져간다.
