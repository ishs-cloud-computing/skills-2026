# set-02 / task-1

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.

## 현재 상태

- 구성: Terraform(VPC·SG·KMS·S3·ECR·DynamoDB·Lambda·ALB·CloudFront·IAM) + eksctl(EKS 1.35,
  addon/app NG, IRSA) + k8s(book 앱, kube-prometheus-stack, Fluent Bit). 런북은
  README.md(PS7, 주) / README.linux.md(bash, 부). 플레이스홀더는 전부 `${ENV_VAR}`
  (envsubst 스타일)로 통일 — k8s 는 `rendered/` 로 렌더 후 `kubectl apply -R -f rendered/` 일괄 적용.
- 미해결: 없음 (실배포 검증은 대회 계정에서만 가능한 항목 잔존 — grafana TGB 선적용 재시도 확인 등)

## 채점 커버리지

- mark.sh 전 항목 구현 완료 상태로 인계받음 (README 요구사항 ↔ 구현 매핑 표 참조).
  이번 변경은 런북 절차(렌더 검증·일괄 apply)만 바꾸며 리소스 구성엔 손대지 않았다.

## 실측 소요시간

- terraform apply: (미실측)
- EKS 노드 준비: eksctl create cluster 약 20분 (README 기준)
- 기타 병목: CloudFront Deployed 전파 수 분

---
## 결정 로그

### 2026-07-27 k8s manifest 를 rendered/ 로 일괄 렌더 후 폴더 단위 apply
- 맥락: 파일별 인라인 Replace 파이프는 치환 누락·env 미선언을 조용히 통과시킴.
  치환 전 env 검사 + 치환 후 잔여 `${}` 검사를 넣으려면 렌더 결과가 파일로 남아야 한다.
- 채택: `<X>` 플레이스홀더를 `${ENV_VAR}`(env 변수명과 일치)로 통일, set-03 의 정규식
  렌더 패턴 재사용. k8s 전체를 `k8s/rendered/` 미러로 렌더 → `kubectl apply -R -f rendered/`
  한 번. helm values 는 kubectl 대상이 아니라 제외하고 `kps-values.rendered.yaml` 로 따로 렌더.
  Grafana 계정도 terraform output(`grafana_admin_user`/`grafana_admin_password`)으로 뽑아
  §1 에서 다른 값들과 한 번에 env 화 — 셸별 `$korea26!!` 이스케이프를 런북에서 제거.
- 기각: envsubst 단독(PS 미지원 + 미선언 변수를 빈 값으로 조용히 치환) → 사전 검사 필수.
  kustomize → 도구 추가 없이 폴더 apply + 번호 prefix 로 충분.
- 대가: grafana TGB 가 서비스(helm kps)보다 먼저 apply 됨 — LBC 가 재시도해 서비스 생성 후
  자동 바인딩되는 동작에 의존. 파일별 apply 순서 제어는 포기 (00- prefix 사전순으로 대체).
