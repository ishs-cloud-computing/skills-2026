---
title: "변수 설계"
sidebar:
  order: 5
---

| 변수 | 기본값 | 비고 |
|---|---|---|
| `bibunho` | (tfvars 필수) | S3 버킷명 suffix |
| `region` | `ap-northeast-2` | 엔드포인트 서비스명·env에 공유 |
| `name_prefix` | `gj2026` | 전 리소스명 파생 |
| `vpc_cidr` / `private_subnet_cidrs` | 10.0.0.0/16, [10.0.10.0/24, 10.0.11.0/24] | Fluent Bit AZ 판별 정규식도 이 값에서 생성 |
| `azs` | `["ap-northeast-2a","ap-northeast-2b"]` | 로그 스트림 이름과 단일 소스 |
| `cluster_version` | `1.35` | |
| `addon_instance_type` / `app_instance_type` | t3.medium / m5.large | |
| `node_desired_size` | 2 | 두 노드그룹 공통 |
| `table_name` | `books` | env `TABLE_NAME`과 단일 소스 |
| `gsi_name` | `client_id-index` | Lambda 코드에도 주입 |
| `container_port` | 8080 | TG·SG·Service 공유 |
| `image_tag` | `latest` | 채점이 latest 태그를 지정 |
| `grafana_admin_password` | `Skills53#` | |
| `client_id_regex` | `^[A-Za-z][A-Za-z]*[0-9][A-Za-z0-9]*$` | WAF 규칙 변경 대비 |
| `enable_ddb_write_deny` | `true` | 데이터 정리 시 일시 false |
