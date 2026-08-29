---
paths:
  - "**/eksctl/**"
---

- **완료 조건은 "클러스터가 존재한다" 가 아니다.** 일반 CloudShell 에서 `aws eks update-kubeconfig --name <클러스터> --region <리전>` **한 줄** 뒤 `kubectl get nodes` 가 돼야 한다. 채점 중 그 외 명령은 허용되지 않는다. 전문: [eks-grading.md](../context/eks-grading.md)
- 채점 주체 principal 의 접근 권한이 들어가 있어야 한다. 기본값 Access Entry — 채점 주체가 생성자와 같으면 `authenticationMode: API`, 다르면 `API_AND_CONFIG_MAP` + `accessEntry`.
- 앱 권한 기본은 Pod Identity. 채점이 SA 의 `role-arn` annotation 을 읽으면 **IRSA**(`iam.withOIDC: true` + `iam.serviceAccounts`).
- `eksctl`·`helm` 은 **버전 간 기본값·스키마가 자주 바뀐다**(옵션 deprecated, 기본값 변경). 옵션을 쓰기 전에 `eksctl utils schema` · `helm show values` 또는 공식 문서로 현재 동작을 확인한다.
- 버전을 고정하지 않는 예외: eksctl·helm·EKS Addon 은 최신 안정 버전. AL2023 등 보안 항목과 과제지 명시 버전은 그대로 따른다.
- `cluster.yaml` 변경은 **Terraform `plan` 에 잡히지 않는다.** eksctl 쪽에서 따로 확인한다.
- 과제지가 요구하지 않는 bastion 은 감점 대상이다.
