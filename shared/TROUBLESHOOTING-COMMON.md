# Common troubleshooting

KIT 고유의 설정 값은 해당 KIT README에 남긴다. 여기에는 여러 KIT에 공통인 실행 실패만 둔다.

## RUN guard — 적용 전 확인

각 KIT README의 대상 Terraform 디렉터리에서 아래 순서로 확인한다. addon은 README의 파일을 대상 Kit에 **COPY**한 뒤 그 대상 Terraform 디렉터리에서 실행한다. addon 자체를 독립적으로 `apply`하지 않는다.

```text
EXPECTED ACCOUNT: 대회 당일 지급받은 계정
EXPECTED REGION:  과제지와 contest.tfvars에 적힌 대상 리전
CHECK BEFORE APPLY: aws sts get-caller-identity
```

```powershell
aws sts get-caller-identity
aws configure get region
terraform version
```

- 출력 계정은 대회 당일 지급 계정이어야 하고, 리전은 과제지·`terraform.tfvars`의 리전과 같아야 한다. 다르면 apply하지 않는다.
- `terraform init -upgrade`는 사용하지 않는다. `.terraform.lock.hcl`이 있는 Kit은 그 lock file에 고정된 provider로 `terraform init`만 실행한다. lock file이 없는 기존 Kit은 provider를 추정해 고정하거나 업그레이드하지 말고, 공식 검증본/지급물을 확인한다.
- `terraform plan`에 기존 리소스의 replace/delete 또는 예상 밖 변경이 보이면 중단하고, 복사한 addon의 이름·변수·대상 리소스를 다시 확인한다.

## 자주 나는 실패

| 증상 | 먼저 할 일 |
| --- | --- |
| `AccessDenied` | 기존 제공 리소스를 수정·삭제하려 한 것은 아닌지 확인한다. 과제지에 요구된 IAM Role/Policy 생성에서 난 오류라면 감독에게 Deny 정책 여부를 확인한다. |
| 이름이 이미 존재 | 기존 리소스를 지우지 말고, 새로 부착한 리소스의 이름 변수를 과제지 범위 안에서 바꾼다. |
| provider/lock 불일치 | `versions.tf`와 `.terraform.lock.hcl`을 확인하고 `init -upgrade` 대신 현재 고정 버전으로 다시 `terraform init`한다. |
| CloudFront 또는 WAF 오류 | CloudFront 범위 WAF는 `us-east-1` provider alias가 필요한지 해당 README와 기존 세트 구현을 확인한다. |
| EKS 채점 접근 불가 | 일반 CloudShell에서 `aws eks update-kubeconfig --name <cluster> --region <region>` 한 번 후 `kubectl get nodes`를 확인한다. bastion 삭제는 이 확인 뒤에만 한다. |
| 채점 스크립트가 실행되지 않음 | CloudShell에서 스크립트의 CRLF를 제거하고, 공식 `mark.md`가 지시한 위치·순서로 실행한다. |

## VERIFY와 SCORE

- **VERIFY:** 배포한 KIT의 리소스·endpoint·로그·Kubernetes object가 기대한 형태인지 확인한다.
- **SCORE:** 세트의 공식 `mark.md`, `mark.sh`, `mark*.sh`를 기준으로 채점 상태를 확인한다.

대회 당일 기본 RUN에는 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
