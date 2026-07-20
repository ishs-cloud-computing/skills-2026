---
title: "변수 설계"
sidebar:
  order: 5
---

## Terraform 변수 (`variables.tf`)

| 변수 | 기본값 | 비고 |
|---|---|---|
| `bibunho` | (tfvars 필수) | S3 버킷명 suffix |
| `region` | `ap-northeast-2` | 엔드포인트 서비스명·env에 공유 |
| `name_prefix` | `gj2026` | 전 리소스명 파생 |
| `vpc_cidr` / `private_subnet_cidrs` | 10.0.0.0/16, [10.0.10.0/24, 10.0.11.0/24] | Fluent Bit AZ 판별 정규식도 이 값에서 생성 |
| `azs` | `["ap-northeast-2a","ap-northeast-2b"]` | 로그 스트림 이름과 단일 소스 |
| `cluster_version` | `1.35` | eksctl `cluster.yaml` 의 `version` 과 수동 동기화 |
| `table_name` | `books` | env `TABLE_NAME`과 단일 소스 |
| `gsi_name` | `client_id-index` | Lambda 코드에도 주입 |
| `container_port` | 8080 | TG·SG·Service 공유 |
| `grafana_port` | 3000 | TG·SG 공유 |
| `image_tag` | `latest` | 채점이 latest 태그를 지정 |
| `client_id_regex` | `^[A-Za-z][A-Za-z]*[0-9][A-Za-z0-9]*$` | WAF 규칙 변경 대비 |
| `enable_ddb_write_deny` | `true` | 데이터 정리 시 일시 false |
| `lambda_runtime` / `metric_namespace` / `log_group_name` | python3.14 / gj2026/reservation / /eks/book-svc/access | |

## eksctl / k8s 고정값 — 당일 변경 시 직접 수정

eksctl·helm values 는 Terraform 변수를 못 쓴다. 동적 값(서브넷 ID·SG·ARN)은
`${VAR}` 플레이스홀더로 런북에서 치환하고, 아래 항목은 파일에 리터럴로 존재한다.
당일 요구사항이 바뀌면 해당 파일에서 검색·치환한다.

| 값 | 현재값 | 위치 |
|---|---|---|
| 인스턴스 타입 | t3.medium(addon) / m5.large(app) | `eksctl/cluster.yaml` `instanceType` |
| 노드 수 | 2 / 2 | `eksctl/cluster.yaml` `desiredCapacity·minSize·maxSize` |
| 리전·AZ | ap-northeast-2(a·b) | `eksctl/cluster.yaml`, `k8s/` 전반 (`grep -r ap-northeast-2`) |
| 클러스터명·prefix | gj2026 | `eksctl/cluster.yaml`, `k8s/lbc-values.yaml` 등 (`grep -r gj2026`) |
| Grafana admin 비밀번호 | `Skills53#` | `k8s/monitoring/grafana-values.yaml` `adminPassword` |
