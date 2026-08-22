# shared/addons — 1과제 당일 추가 문항 부착 키트

1과제 출제지침의 옵션 5개(KMS / WAF / Security / Lambda GET API / Observability) 중
당일 추가된 문항을 기존 task-1 에 부착하기 위한 스니펫 모음.
기존 문항·리소스는 건드리지 않는다 (DAY-OF 1절 — 당일 변동은 추가 방식).

추가 문항을 찾을 때는 [KIT-INDEX](../../KIT-INDEX.md)를 authoritative source로 쓰고, 자주 쓰는 표현은 [QUICK-REFERENCE](../../QUICK-REFERENCE.md)에서 먼저 찾는다. 각 addon은 **COPY** 방식이며 독립 Terraform state나 독립 `apply` 대상이 아니다.

## 카테고리 → 준비물

| 옵션 | 스니펫 | 실전 구현 (참고용) |
| --- | --- | --- |
| KMS | `kms/` | set-07 task-1 `terraform/kms.tf` (CMK 3개·MRK·서비스별 key policy) |
| WAF | `waf/` | set-07 task-1 `terraform/waf.tf` (CLOUDFRONT), task-3 `terraform/waf.tf` (scope-down·base64) |
| Security (IRSA·Pod Identity·OIDC) | `irsa/` | set-08 task-2 module-4 `eksctl/cluster.yaml` (IRSA), set-07 task-1 `eksctl/cluster.yaml` (Pod Identity) |
| Lambda GET API | `lambda-get-api/` | set-07 task-1 `terraform/lambda.tf`·`lambda/`, set-05 task-2 module-4 (REST API) |
| Observability | `observability/` | set-07 task-1 `k8s/monitoring/`·`k8s/logging/`·`terraform/cloudwatch.tf` |

## 부착 절차

1. 종이 과제지의 신규 문항(분홍)을 위 표에 매핑한다.
2. 스니펫 `.tf` 를 `set-XX/task-1/terraform/` 으로 복사한다. `variables.tf` 스니펫의 변수 선언도 같이 복사한다.
3. 과제지 명시 이름·수치를 `terraform.tfvars` 에 넣는다. 이름 정확 일치가 채점 항목이다.
4. 기존 변수와 이름이 충돌하면 스니펫 쪽 변수를 리네임한다. 기존 리소스는 수정하지 않는다.
5. `terraform fmt` → `validate` → `plan` 으로 기존 리소스에 diff 가 없는지 확인 후 apply.
6. eksctl 스니펫(irsa/)은 기존 클러스터에 `eksctl create ...` 한 줄로 부착한다. 클러스터 재생성 금지.

## 금지선 (출제지침)

- 1과제에 인프라 스케일링 문제는 출제되지 않는다.
- 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx) 불가.
- Helm 은 채점요소가 될 수 없다 — 채점 대상 리소스는 helm 없이도 확인 가능한 형태(AWS 리소스·k8s 오브젝트)로 만든다.
