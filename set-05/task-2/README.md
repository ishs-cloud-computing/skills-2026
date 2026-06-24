# set-05 / task-2 — Small challenge

제2과제는 **독립 모듈 4개**로 구성된다(각 7.5점, 합계 30점). 모듈마다 리전이 다르므로 서로 독립적으로 배포·채점한다.

| 모듈 | 주제 | 리전 | 핵심 서비스 | 채점 |
|------|------|------|-------------|------|
| [module-1-eks-scaling](module-1-eks-scaling/) | EKS Scaling | ap-northeast-2 | EKS + KEDA(SQS) + Karpenter | Bastion |
| [module-2-vpc-lattice](module-2-vpc-lattice/) | VPC Lattice | ap-southeast-1 | Hub/Spoke VPC + Internal ALB + VPC Lattice | Bastion |
| [module-3-container-logging](module-3-container-logging/) | Container Logging | ap-northeast-1 | EC2 Docker + Fluent Bit → Loki/Grafana | Bastion |
| [module-4-rest-api](module-4-rest-api/) | REST API Implement | us-east-1 | API Gateway + Lambda + DynamoDB | CloudShell |

## 공통 워크플로

```bash
# 각 모듈 디렉터리에서 독립적으로 배포
cd module-<n>-<name>/terraform
terraform init && terraform apply -auto-approve
# 이후 모듈별 README 의 "배포 순서" 를 따른다 (eksctl / helm / k8s / 앱).
```

공식 채점 스크립트는 `mark/`(mark1~4.sh)에, 제공 배포파일은 `provided/`(2-2 VPC Lattice 앱, 2-3 Container Logging 앱)에 있다. 제공 배포파일은 수정하지 않으며 각 모듈 terraform이 직접 참조한다. mark1/2/3은 각 모듈 Bastion에서, mark4는 CloudShell에서 실행한다.

```bash
# 채점 시 기본 리전 설정 (채점지 사전 작업)
aws configure set default.region ap-northeast-2   # module-1
aws configure set default.region ap-southeast-1   # module-2
aws configure set default.region ap-northeast-1   # module-3
aws configure set default.region us-east-1        # module-4
```

## 공통 규칙

- 리소스 이름은 과제지에 명시된 값과 **정확히 일치**(이름 일치 채점 항목 다수).
- Security Group 80/443 outbound는 anyopen, Bastion은 재시작 후에도 EIP로 IP 고정.
- Terraform은 AWS 리소스, EKS 클러스터는 `eksctl`, KEDA/Karpenter/Loki/Grafana는 helm + 체크인된 values/manifest.
- 모듈 4는 Lambda Runtime `python3.14` 인식을 위해 AWS provider `>= 5.80`(6.x), 나머지는 `~> 5.60`.

> 설계 근거·요구사항↔구현 매핑·주의 포인트는 각 모듈 README 하단을 참고한다.
