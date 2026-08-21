# Security (IRSA · Pod Identity · OIDC) 부착 스니펫

1과제 Security 옵션의 핵심은 "Pod 에 IAM 권한을 어떻게 주는가"다. 방식 판정부터 한다.

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 세트의 `k8s/`·`eksctl/`(또는 기존 구성)으로 복사해 병합한다. 이 addon 디렉터리 자체는 독립 `apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
kubectl config current-context
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`/`delete`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 방식 판정 (CLAUDE.md 규칙)

- 기본값: **Pod Identity**.
- 채점 스크립트가 ServiceAccount 의 `eks.amazonaws.com/role-arn` **annotation 을 직접 읽으면 IRSA**.
  Pod Identity 는 그 annotation 을 만들지 않아 무조건 미충족이다 (set-08 task-2 채점 4-2 실례).
- 과제지가 "OIDC" 를 명시해도 같은 판정 — OIDC provider 는 IRSA 의 전제 조건이다.

## 신규 클러스터 (cluster.yaml 에 블록 추가)

IRSA — set-08 task-2 module-4 `eksctl/cluster.yaml` 원본:

```yaml
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: <SA이름>
        namespace: <네임스페이스>
      attachPolicyARNs:
        - "${POLICY_ARN}"   # terraform output 치환. 재조립 금지 — ARN 그대로 쓴다
```

Pod Identity — set-07 task-1 `eksctl/cluster.yaml` 원본:

```yaml
iam:
  podIdentityAssociations:
    - namespace: <네임스페이스>
      serviceAccountName: <SA이름>
      roleARN: "${ROLE_ARN}"   # trust = pods.eks.amazonaws.com
addons:
  - name: eks-pod-identity-agent   # 없으면 association 이 있어도 자격증명이 안 나온다
```

## 기존 클러스터에 당일 부착 (재생성 금지)

```powershell
# IRSA — OIDC provider 없으면 먼저 연동
eksctl utils associate-iam-oidc-provider --cluster <클러스터> --region <리전> --approve
eksctl create iamserviceaccount --cluster <클러스터> --region <리전> `
  --namespace <ns> --name <sa> --attach-policy-arn <POLICY_ARN> `
  --role-name <과제지_지정_Role_이름> --approve
# SA 가 이미 있으면 --override-existing-serviceaccounts 추가

# Pod Identity
eksctl create addon --cluster <클러스터> --region <리전> --name eks-pod-identity-agent
eksctl create podidentityassociation --cluster <클러스터> --region <리전> `
  --namespace <ns> --service-account-name <sa> --role-arn <ROLE_ARN>
```

부착 후 Pod 를 재시작해야 자격증명이 주입된다: `kubectl rollout restart deployment/<이름>`.

## Role·Policy 는 Terraform 에서

- Role 이름이 과제지에 명시되면 정확히 일치시킨다 — 채점 스크립트가 Role 을 직접 읽는다.
- Pod Identity 용 trust: principal `pods.eks.amazonaws.com` + `sts:AssumeRole`·`sts:TagSession`.
  본 클러스터 한정 조건까지 거는 패턴은 set-07 task-1 `terraform/iam.tf` 참고.
- IRSA 용 trust(OIDC federated) 는 eksctl `create iamserviceaccount` 가 만들어 주므로
  Terraform 으로는 policy 만 만들고 ARN 을 넘기는 쪽이 빠르다. Role 이름까지 지정된 경우
  `--role-name` 으로 준다.

## 검증

```powershell
# IRSA — annotation 존재가 채점 형태
kubectl get sa <sa> -n <ns> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# Pod Identity
aws eks list-pod-identity-associations --cluster-name <클러스터> --region <리전>
# 공통 — Pod 안에서 실제 신원 확인
kubectl exec deploy/<이름> -n <ns> -- aws sts get-caller-identity
```
