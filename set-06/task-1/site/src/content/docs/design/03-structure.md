---
title: "디렉토리 구조"
sidebar:
  order: 3
---

```
set-06/task-1/
├── terraform/
│   ├── providers.tf      # provider 버전 고정, required_version
│   ├── variables.tf      # 기본값
│   ├── terraform.tfvars  # 비번호 등 세트 값 주입
│   ├── vpc.tf            # VPC·Subnet·IGW·RT·Gateway Endpoint(s3/dynamodb)·Interface Endpoint·SG
│   ├── kms.tf            # CMK 3종(db/s3/eks) + alias + 키 정책
│   ├── ecr.tf            # book repository + pull-through cache rule(ecr-public)
│   ├── dynamodb.tf       # 테이블·GSI·리소스 기반 정책
│   ├── alb.tf            # ALB·TG 2종(book/grafana)·Listener·Rule
│   ├── lambda.tf         # 함수·Function URL·OAC·권한
│   ├── lambda/index.py   # 조회 API + EMF 메트릭 (Function URL 이벤트 포맷)
│   ├── s3.tf             # 버킷·BPA·OAC 정책·정적 객체 업로드
│   ├── cloudfront.tf     # VPC Origin·Lambda OAC Origin·Distribution·Function·캐시 정책
│   ├── waf.tf            # Web ACL(CLOUDFRONT scope, us-east-1 provider) + custom response
│   ├── iam.tf            # IRSA 역할(book/lambda/fluent-bit/grafana/LBC)
│   └── outputs.tf        # CF 도메인·배포 ID·ECR URL·TG ARN·ENI IP 등
├── eksctl/
│   └── cluster.yaml      # 클러스터 + Bottlerocket 노드그룹 2개
├── k8s/
│   ├── 00-namespace.yaml
│   ├── app/              # configmap·deployment·service·securitygrouppolicy·targetgroupbinding
│   ├── monitoring/       # grafana values·dashboard configmap·targetgroupbinding
│   └── logging/          # fluent-bit values(파서·rewrite_tag)
├── app/Dockerfile        # scratch + 제공 바이너리 (zstd push)
├── plan.md · task.md · task.pdf · mark.md · mark.pdf · mark.sh
└── README.md             # 런북 (구현 시 작성)
```

제공 배포파일은 `shared/provided/set-06-task-1/` 에 원본 그대로 둔다(수정 금지).
