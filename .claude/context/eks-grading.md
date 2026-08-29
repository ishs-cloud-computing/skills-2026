# EKS 채점 접근

> CLAUDE.md 라우팅에서 **"EKS 과제를 설계·검증할 때"** 읽는다. `eksctl/`·`k8s/` 파일을 편집하면 [`.claude/rules/eksctl.md`](../rules/eksctl.md) 가 요약을 자동으로 붙인다.

k8s 채점은 **선수의 일반 CloudShell** 에서 진행한다. 채점자가 클러스터에 못 붙으면 **그 항목은 전부 날아간다.**

## 완료 조건

채점 중 허용되는 명령은 다음 **한 줄뿐**이다. 자격증명 입력이나 그 외 명령은 허용되지 않는다.

```
aws eks update-kubeconfig --name <클러스터> --region <리전>
```

따라서 EKS 과제의 완료 조건은 "클러스터가 존재한다" 가 아니라
**"일반 CloudShell 에서 위 한 줄 뒤 `kubectl get nodes` 가 된다"** 이다.

채점 신원은 **CloudShell 을 실행한 IAM User 또는 Role** 이다.

## 인증 방식

인증 방식은 자유이나(Access Entry / aws-auth), **채점 주체 principal 의 접근 권한이 들어가 있어야 한다.**

저장소 기본값은 **Access Entry**:

| 채점 주체 | `authenticationMode` | 추가 |
| --- | --- | --- |
| 클러스터 생성자와 같음 | `API` | — |
| 다름 | `API_AND_CONFIG_MAP` | `accessEntry` |

## bastion

- 과제지가 요구하지 않는 bastion 은 **불필요 리소스 감점 대상**이다.
- 만들 수는 있으나 불이익은 선수 부담이고, **채점 중에는 생성도 시작도 못 한다.** 채점 때 쓸 거면 그 시점에 이미 running 이어야 한다.
- 작업용 bastion 을 채점 전에 지운다면 **지우기 전에 CloudShell 경로를 먼저 검증한다.** 지운 뒤에 권한이 없다는 걸 알면 손쓸 방법이 없다.
- 3과제는 EC2 인스턴스 수가 채점 축이다 — 작업용 bastion 을 아예 두지 않는다.

## 앱 권한: Pod Identity vs IRSA

기본은 **Pod Identity**. 단 **채점 스크립트가 ServiceAccount 의 `eks.amazonaws.com/role-arn` annotation 을 직접 읽으면 IRSA 로 간다** (`iam.withOIDC: true` + `iam.serviceAccounts`).

Pod Identity 는 그 annotation 을 만들지 않아 **무조건 미충족**이다.

set-08 task-2 채점 4-2 가 실제로 이 annotation 을 검사하므로 **module-4 는 IRSA 다. Pod Identity 로 "정정" 하지 말 것.**

## 세션이 끊겨도 바로 잇는다

bastion·CloudShell 환경변수는 연결이 끊겨도 **재접속 시 그대로 쓸 수 있게 `.env` 파일로** 준비한다 (bastion 과 로컬 양쪽).
`.env`·`.env.ps1` 은 `.gitignore` 대상이다 — 커밋하지 않는다.
KIT 부착용 실제 리소스 ID 는 `shared\scripts\discover.ps1 -Region <리전>` 이 `addon.<리전>.env` 로 뽑아준다.
