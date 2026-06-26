# 2026년도 전국기능경기대회 — 제1과제 문제지

| 직종명 | 과제명 | 과제번호 |
|---|---|---|
| 클라우드컴퓨팅 | Solution Architecture | 제1과제 |

| 경기시간 | 비번호 | 심사위원 확인 |
|---|---|---|
| 4시간 | | (인) |

## 1. 요구사항

당신은 Worldskills에서 클라우드 솔루션을 활용하여 어플리케이션이 동작할 수 있는 IT 인프라를 구성하는 업무를 맡고 있습니다. 아래 다이어그램과 주어진 요구사항, 클라우드의 설계원칙인 고가용성, 확장성, 비용, 보안 등을 잘 고려하여 인프라를 구축하여야 합니다.

> 다이어그램

### Software Stack

| AWS | 개발언어/CNCF/Tools |
|---|---|
| VPC, EC2, EKS, ECR, DynamoDB, ALB, IAM, KMS, Route53, CloudWatch, Lambda, CloudFront, WAF, S3 | Python, Grafana, Fluentbit |

## 2. 선수 유의사항

1. 기계 및 공구 등의 사용 시 안전에 유의하시고, 필요 시 안전장비 및 복장 등을 착용하여 사고를 예방하여 주시기 바랍니다.
2. 작업 중 화상, 감전, 찰과상 등 안전사고 예방에 유의하시고, 공구나 작업도구 사용 시 안전보호구 착용 등 안전수칙을 준수하시기 바랍니다.
3. 작업 중 공구의 사용에 주의하고, 안전수칙을 준수하여 사고를 예방하여 주시기 바랍니다.
4. 경기 시작 전 가벼운 스트레칭 등으로 긴장을 풀어주시고, 작업도구의 사용 시 안전에 주의하십시오.
5. 모든 리소스는 서울(ap-northeast-2) 리전에 구성합니다.
6. 제공자료는 수정 없이 사용합니다. 제공자료를 수정해서 사용하면 불이익을 받을 수 있습니다.
7. 모든 리소스의 이름, 태그, 변수는 대소문자를 구분합니다.
8. 문제에서 별도로 주어지지 않은 값은 기본값으로 설정해야 합니다.

## 3. Network Configuration

- Reference01의 표를 참고하여 VPC를 생성합니다.
- VPC에는 인터넷 통신이 불가능한 Private subnet만 있습니다.
- CloudFront VPC Origin 연동을 위해 Internet Gateway를 VPC에 연결합니다.

## 4. Application

- Book 애플리케이션은 1개의 POST API를 가지고 있습니다. (Reference02 참고)
- 앱의 헬스체크는 `/health`로 이루어집니다.
- 앱은 DynamoDB 관련 설정을 리눅스 환경변수(`AWS_REGION`, `TABLE_NAME`)로 전달받습니다.

## 5. Container Registry

- 애플리케이션 컨테이너 이미지 저장을 위해 ECR을 사용합니다.
- ECR에 저장되는 이미지의 크기는 3MB를 초과할 수 없습니다.
- 클러스터 운영 중 추가로 필요한 외부 이미지는 Private ECR을 통해 제공되어야 합니다.
- 채점은 Public ECR 레지스트리(`public.ecr.aws`) 이미지를 통해 확인합니다.

> Book Repository Name: `book`

## 6. Database

- 예약 정보를 저장하기 위한 NoSQL 데이터베이스로 DynamoDB를 사용합니다.
- 고객 관리형 키(CMK)를 사용하여 저장 데이터를 암호화해야 합니다.
- Client ID로 예약 내역을 조회할 수 있도록 GSI를 구성해야 합니다.
- DynamoDB 테이블에 대한 쓰기 권한은 book 애플리케이션만 허용합니다.
- 채점 전에 어떠한 데이터 항목이 있어도 안됩니다.

> Table Name: `books`
> Partition Key: `booking_id`
> KMS Key: `alias/gj2026-db-key`
> GSI Name: `client_id-index` / Partition Key: `client_id`

## 7. Container

- 제공된 Application을 Container 환경에 배포하기 위해 AWS EKS를 사용합니다.
- 고가용성을 고려해야 하며, Private 환경에서 애플리케이션이 실행되어야 합니다.
- Secret Resource들은 반드시 KMS Encryption 되어야 합니다.
- 워커 노드는 bottlerocket AMI를 사용합니다.
- 주어진 Application들은 `skills` 라는 Namespace를 사용하여 EKS Cluster 내에서 논리적으로 분리시켜야 합니다.
- Daemonset 이외에 모든 Addon은 Addon NodeGroup에 배포해야 합니다.

> EKS Cluster Name: `gj2026-eks-cluster`
> EKS Cluster Version: `1.35`
> KMS Key Alias: `alias/gj2026-eks-key`

### Addon Nodegroup

- 애플리케이션을 제외한 모든 Addon들은 반드시 Addon Nodegroup에서 운용해야 합니다.
- 2개의 노드를 운용해야 합니다.
- cluster에 등록되는 노드 이름은 `gj2026.<instance_id>.addon.node` 형식으로 변경합니다.

> Nodegroup Name: `gj2026-eks-addon-nodegroup`
> Node EC2 Instance Tag: `Name=gj2026-eks-addon-node`
> Node EC2 Instance Type: `t3.medium`

### App Nodegroup

- App Nodegroup에서는 애플리케이션을 운용해야 합니다.
- 애플리케이션을 제외한 다른 리소스들은 App Nodegroup에 존재해서는 안됩니다.
- cluster에 등록되는 노드 이름은 `gj2026.<instance_id>.app.node` 형식으로 변경합니다.
- 2개의 노드를 운용해야 합니다.

> Nodegroup Name: `gj2026-eks-app-nodegroup`
> Node EC2 Instance Tag: `Name=gj2026-eks-app-node`
> Node EC2 Instance Type: `m5.large`

## 8. Application Deployment

- book 애플리케이션은 `skills` Namespace에 배포되며, 2개 운용되어야 합니다.
- book 애플리케이션은 ALB에서 오는 요청만 수신할 수 있어야 합니다.

> book Deployment Name: `book`
> book Service Name: `book-svc`

## 9. Load Balancing

- 로드밸런서는 인터넷에서 직접 접근할 수 없어야 하며, Private 서브넷에 배치되어야 합니다.
- Grafana 대시보드는 ALB의 `/grafana` 경로를 통해 접근할 수 있어야 합니다.
- 단기간에 많은 트래픽이 들어와도 로드밸런싱되어야 합니다.

> ALB Name: `gj2026-alb`
> Book Target Group Name: `gj2026-book-tg`
> Grafana Target Group Name: `gj2026-grafana-tg`

## 10. Static Web Hosting

- S3를 통하여 정적 콘텐츠를 저장하고 제공합니다.
- 모든 콘텐츠는 업로드 시 자동으로 CMK로 암호화되어야 합니다.
- 모든 콘텐츠 파일은 루트 디렉토리에 업로드 합니다.

> S3 Bucket Name: `gj2026-static-<비번호>`
> KMS Key Alias: `alias/gj2026-s3-key`

## 11. Lambda

- DynamoDB에 저장한 예약 데이터를 조회하는 Lambda 함수를 생성합니다.
- Lambda는 2개의 GET API를 가지고 있습니다. (세부 사항은 Reference03 참고)

> Lambda function Name: `gj2026-book-reservation`
> Lambda Runtime: `python3.14`

## 12. CDN

- CloudFront를 통하여 정적 콘텐츠 및 어플리케이션에 접근이 가능하도록 합니다.
- ALB로의 요청에 대해서는 캐싱하지 않고 Query String도 모두 Origin으로 전달해야 합니다.
- S3로의 요청에 대해서는 캐싱되어야 합니다.
- 사용자가 CloudFront에 HTTP 접근 시에도 HTTPS로 리디렉션 되어 HTTPS로만 접근할 수 있도록 구성합니다.
- `/reservation`으로 시작하는 요청 시 lambda가 호출되어야 합니다.
- URL에 확장자가 없는 경우 `index.html`로 자동 라우팅되어야 합니다.

> CloudFront Name: `gj2026-cdn`
> VPC Origin Name: `gj2026-alb-origin`

## 13. WAF

- WAF Web ACL을 생성하여 보안을 강화합니다.
- ALB 요청에서 POST 이외의 HTTP 메서드를 사용한 요청은 자동으로 차단되어야 하며 "Method Not Allowed" 문구와 405 응답 코드를 반환해야 합니다.
- Lambda 요청에 대해 `client_id` 쿼리 파라미터가 존재하는 경우, 영문자로 시작하고 뒤에 숫자가 포함된 형식만 허용해야 하며 "Access Denied" 문구와 403 응답 코드를 반환해야 합니다.

> WAF Web ACL Name: `gj2026-waf-acl`

## 14. Monitoring

- Lambda 함수 호출 시 `client_id` 별 호출 횟수가 CloudWatch 메트릭으로 수집되며 Grafana 대시보드에서 시각화되어야 합니다. 또한 전체 `client_id`에 대한 조회는 `ALL`로 집계하여 표시해야 합니다.
- book 서비스의 액세스 로그를 Fluent Bit을 통해 수집하고, 액세스 로그의 `remote_addr` 필드에 포함된 ALB 노드의 VPC 내부 IP 대역을 기준으로 가용영역별 CloudWatch 로그 스트림으로 분리하여 전송해야 합니다.

> Grafana Admin Password: `Skills53#`
> Grafana Namespace: `monitoring`
> Grafana Dashboard Name: `WSI Dashboard`
> Fluent Bit Namespace: `logging`
> Fluent Bit Daemonset Name: `aws-for-fluent-bit`
> CloudWatch Log Group: `/eks/book-svc/access`
> CloudWatch Log Stream: `/book-svc/ap-northeast-2a`, `/book-svc/ap-northeast-2b`

---

## Reference01

### VPC

| Name | Cidr |
|---|---|
| gj2026-vpc | 10.0.0.0/16 |

### Subnet

| Name | Cidr | VPC |
|---|---|---|
| gj2026-private-subnet-a | 10.0.10.0/24 | gj2026-vpc |
| gj2026-private-subnet-b | 10.0.11.0/24 | gj2026-vpc |

### Routing Table

| Name | Subnet | Gateway |
|---|---|---|
| gj2026-private-rtb-a | gj2026-private-subnet-a | x |
| gj2026-private-rtb-b | gj2026-private-subnet-b | x |

### Internet Gateway

| Name | VPC |
|---|---|
| gj2026-igw | gj2026-vpc |

## Reference02 — Book

| 항목 | 내용 |
|---|---|
| API | `POST /v1/book` |
| Request | `application/json`<br>- client_id: Client ID (String)<br>- username: 구매자 이름 (String)<br>- email: 구매자 이메일 (String)<br>- concert_name: 콘서트 (String)<br>Sample: `'{"client_id": "C001", "username": "Alice", "email": "kim@example.com", "concert_name": "Seoul2025"}'` |
| Response | Code 200<br>- booking_id: 유니크 예약 ID (String)<br>Sample: `{"booking_id": "C2011YY"}` |
| Description | HTTP 요청의 Body에 있는 필드 값과 `created_at` 필드가 DynamoDB 테이블에 저장됩니다. |

## Reference03 — Lambda

| API | Request | Response |
|---|---|---|
| `GET /reservation` | - | `[{"username": "Alice", "email": "kim@example.com", "concert_name": "Seoul2025"}, ...]` |
| `GET /reservation` | Query String<br>`?client_id=Cxxxxx`<br>Sample: `/reservation?client_id=C001` | `[{"username": "Alice", "email": "kim@example.com", "concert_name": "Seoul2025"}]` |
