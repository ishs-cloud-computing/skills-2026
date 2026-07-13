# 1과제 문제지

2026년도 전국기능경기대회 · 클라우드컴퓨팅 · Web Service Provisioning · 제1과제 (경기시간 4시간)

## 1. 요구사항

당신은 Korea Skills Concert에서 주관하는 2026 Skills Festival Korea의 글로벌 서비스 인프라를 설계 및 운영하는 클라우드 아키텍트입니다. 본 행사는 전세계에서 주목하는 대형 축제로, 전 세계 사용자가 동시에 콘서트 티켓을 예매할 수 있도록 서비스를 구축해야 합니다.

### Software Stack

| AWS | 개발언어 / 프레임워크 |
| --- | --- |
| VPC, ELB, CloudFront, S3, ECR, KMS, Lambda, EKS, DynamoDB | golang / gin |

## 2. 선수 유의사항

1) 기계 및 공구 등의 사용 시 안전에 유의하시고, 필요 시 안전장비 및 복장 등을 착용하여 사고를 예방하여 주시기 바랍니다.
2) 작업 중 화상, 감전, 찰과상 등 안전사고 예방에 유의하시고, 공구나 작업도구 사용 시 안전보호구 착용 등 안전수칙을 준수하시기 바랍니다.
3) 작업 중 공구의 사용에 주의하고, 안전수칙을 준수하여 사고를 예방하여 주시기 바랍니다.
4) 경기 시작 전 가벼운 스트레칭 등으로 긴장을 풀어주시고, 작업도구의 사용 시 안전에 주의하십시오.
5) 문제에 제시된 괄호박스 `< >`는 변수를 뜻하므로 적절히 변경하여 사용해야 합니다.
6) 문제 풀이와 채점의 효율을 위해 Security Group의 80/443 Outbound와 ALB Security Group의 HTTP 80 Inbound는 Anyopen하여 사용할 수 있도록 합니다.
7) 모든 리소스는 서울(ap-northeast-2) 리전에 구성합니다.
8) 제공자료는 수정 없이 사용합니다. 제공자료를 수정해서 사용하면 채점 시 불이익을 받을 수 있습니다.
9) 문제에서 주어지지 않는 값들은 AWS Well-Architected Framework 6 pillars를 기준으로 적절한 값을 설정해야 합니다.
10) 불필요한 리소스를 생성한 경우, 감점 처리 될 수 있습니다. (e.g. EC2 추가 생성)
11) 모든 리소스의 이름, 태그, 변수와 값은 대소문자를 구분합니다.
12) 1페이지의 다이어그램은 구성을 추상적으로 표현한 그림으로, 세부적인 구성은 아래의 요구사항을 만족시킬 수 있도록 합니다. (ex. 서브넷이 2개 이상 존재할 수 있습니다.)
13) 채점을 위해 `wskorea26-vpc-environment-sg`라는 이름의 보안그룹을 생성해야 합니다. 외부에서 접근해 EKS Cluster에 접근할 수 있어야 합니다.

## 3. Network Configuration

클라우드 인프라 구축을 위하여 기본적인 네트워크 구성을 수행합니다. Reference01의 정보를 참고하여 AWS VPC를 생성합니다.

## 4. Simple Storage Service

제공된 index.html과 main.jpeg 파일을 S3 Bucket에 업로드하고, CloudFront를 통해 정적 웹 페이지로 제공되도록 구성합니다. S3 Bucket은 외부에서 접근할 수 없어야 하며, S3 URL을 통한 직접 접근은 금지됩니다. CloudFront URL의 루트 경로로 접근 시 Bucket에 업로드한 index.html 페이지가 표시되어야 하며, 웹 페이지 내 main.jpeg 이미지가 정상적으로 로드되어야 합니다. 모든 S3 객체는 KMS로 암호화되어야 합니다.

- S3 Bucket Name : `wskorea26-concert-bucket-(비번호)`
- Object Path : `/web/main/`
- CMK : `wskorea26-s3-key`

## 5. Application

제공된 book 애플리케이션을 이용해 콘서트 예약 정보를 받아 데이터베이스에 저장할 수 있도록 합니다. Reference02의 정보를 참고하여 애플리케이션을 실행합니다.

## 6. Elastic Container Registry

애플리케이션을 컨테이너 환경에서 실행하기 위해 ECR에 이미지를 업로드합니다. Private 레지스트리를 구성하고 보안 구성을 진행합니다. 업로드 시 이미지 스캐닝이 되어야 하며, 스캐닝된 이미지에 Critical 및 High 취약점이 존재해선 안 됩니다. 이미지는 암호화되어 저장되도록 합니다. 이미지는 stable 이라는 태그를 사용해야 합니다.

- Repository Name : `wskorea26-book-repo`

## 7. NoSQL Database

book 애플리케이션은 콘서트 예매 정보를 저장하기 위해 DynamoDB 테이블을 사용합니다. 콘서트 예매 정보의 안정성을 위해 테이블 삭제방지를 활성화하고, KMS로 암호화해야 합니다.

- Table Name : `wskorea26-data-table`
- Primary Key : `client_id(S)`
- CMK : `wskorea26-dynamodb-key`

## 8. Elastic Kubernetes Service

제공된 애플리케이션을 컨테이너 환경에 배포하기 위해 Amazon EKS를 사용합니다. Control Plane에서 발생하는 모든 로그들을 CloudWatch Logs에서 확인할 수 있어야 하며, 모든 Secret 리소스는 반드시 KMS로 암호화되어야 합니다. 클러스터는 Private 환경에 구성하여 애플리케이션 실행을 위해 ManagedNodegroup을 생성해야 합니다. 주어진 애플리케이션은 `wskorea26` namespace를 사용하여 클러스터 내에서 논리적으로 분리시켜야 합니다.

- Cluster Name : `wskorea26-cluster`
- Cluster Version : `1.35`
- CMK : `wskorea26-eks-key`
- Subnet : `wskorea26-priv-subnet-c`, `wskorea26-priv-subnet-d`

### Addon Nodegroup

Book 애플리케이션을 제외한 나머지 모든 Resource들은 반드시 addon Nodegroup에서 동작해야 합니다. Application Resource들이 해당 노드그룹 위에 존재해서는 안 되며, 고가용성을 고려해 구성해야 합니다. 또한 해당 노드그룹의 노드는 `{node-type: addon}`라는 Label을 가지고 있어야 합니다.

- NodeGroup Name : `wskorea26-addon-ng`
- Node Instance Tag : `Name=wskorea26-addon-node`
- Node Instance Type : `t3.medium`

### Application Nodegroup

Book 애플리케이션은 반드시 Application Nodegroup에서 동작해야 합니다. Addon Resource들이 해당 노드그룹 위에 존재해서는 안 되며, 고가용성을 고려해 구성해야 합니다. 또한 해당 노드그룹의 노드는 `{node-type: app}`이라는 Label을 가지고 있어야 합니다.

- NodeGroup Name : `wskorea26-app-ng`
- Node Instance Tag : `Name=wskorea26-app-node`
- Node Instance Type : `t3.medium`

## 9. Lambda Function

콘서트 예매 정보를 조회하는 Lambda 함수를 구성합니다. 함수는 Python 3.14 런타임으로 작성합니다. Lambda 함수의 IAM Role은 최소 권한 원칙에 따라 설정해야 합니다. Lambda 함수 개발 시 제공된 Reference03을 참조하세요.

- Function Name : `wskorea26-book-lambda`

## 10. Load Balancing

애플리케이션과 Lambda 함수에 접근하기 위해 Application Load Balancer를 사용합니다. `/book` 경로로 들어오는 요청이 각 대상으로 적절히 라우팅 되도록 구성합니다. 사용자는 Load Balancer에 직접 접근할 수 없으며, 반드시 CloudFront를 통해서만 접근할 수 있도록 구성해야 합니다. CloudFront를 통하지 않은 요청에는 403 Forbidden을 응답해야 합니다.

- Load Balancer Name : `wskorea26-book-alb`
- Load Balancer Scheme : Internet-facing
- Load Balancer Listener : HTTP 80

## 11. CloudFront

사용자가 S3로 호스팅하는 웹페이지와 애플리케이션에 접근할 수 있도록 Distribution을 구성합니다. 사용자의 모든 요청은 반드시 CloudFront를 통해서만 처리되어야 합니다. 전세계의 사용자가 빠르게 접근할 수 있도록 구성해야 합니다. HTTP로 접근하는 경우 HTTPS로 리다이렉트 되어야 하며, CloudFront에서 전달하는 요청에는 반드시 `X-Origin-Verify: wskorea26-cf` 헤더가 포함되어야 하고, S3로 전달하는 요청에는 `wskorea26-s3-access` 헤더가 포함되어야 합니다. 루트 경로로 접근 시 S3 웹 페이지가 출력되어야 하며, 캐싱을 활성화합니다. `/book` 경로로 접근 시 ALB로 요청이 전달되어야 합니다.

- Distribution Name : `wskorea26-concert-cf`
- ALB Origin ID : `wskorea26-alb-origin`
- S3 Origin ID : `wskorea26-s3-origin`

## 12. Monitoring

클러스터의 메트릭과 로그를 수집하고 시각화하기 위해 모니터링 환경을 구성합니다. 클러스터 메트릭을 수집하고, Pod 로그를 CloudWatch Logs로 전송해야 합니다. 수집된 데이터는 Grafana 대시보드를 통해 시각화할 수 있어야 합니다. 모든 모니터링 컴포넌트는 Addon Nodegroup의 monitoring ns에서 동작해야 합니다. Grafana Dashboard에 접속하기 위해 ALB를 구성합니다. HTTP 80 포트로 접근 시 Grafana Web에 접근할 수 있어야 합니다.

- Dashboard Name : `wskorea26-monitoring`
- Grafana ALB Name : `wskorea26-grafana-alb`
- Grafana Authentication : `skills-<비번호>-admin` | `$korea26!!`

아래 메트릭을 Grafana 대시보드 패널로 표시할 수 있어야 합니다.

- 컨테이너의 CPU 사용량
- 컨테이너의 메모리 사용량
- 실행 중인 Pod 개수
- 컨테이너의 재시작 횟수
- 컨테이너의 네트워크 트래픽 수신량

## Reference01 — VPC / Subnet

| VPC Name | VPC CIDR |
| --- | --- |
| wskorea26-vpc | 172.16.0.0/16 |

| Subnet Name | Subnet CIDR | Route Table | Internet Access |
| --- | --- | --- | --- |
| wskorea26-pub-subnet-c | 172.16.1.0/24 | wskorea26-public-rtb | book-igw (IGW) |
| wskorea26-pub-subnet-d | 172.16.2.0/24 | wskorea26-public-rtb | book-igw (IGW) |
| wskorea26-priv-subnet-c | 172.16.201.0/24 | wskorea26-private-rtb-c | book-ngw-c (NAT) |
| wskorea26-priv-subnet-d | 172.16.202.0/24 | wskorea26-private-rtb-d | book-ngw-d (NAT) |

## Reference02 — Book Application

Book 애플리케이션은 콘서트 예약 정보를 받아 DynamoDB에 저장하는 REST API입니다. 애플리케이션은 `AWS_REGION`과 `TABLE_NAME` 환경변수를 필요로 하며, 8080 포트로 바인딩됩니다.

| Path | Method | Request Body | Response |
| --- | --- | --- | --- |
| /v1/book | POST | client_id, username, email, concert_name | booking_id |
| /health | GET | - | 200 OK |

Request Example:

```json
{"client_id": "C1020", "username": "chuu", "email": "jiwo@atrp.com", "concert_name": "2ND_TINY_CON"}
```

Response:

```json
{"booking_id": "97E53A10"}
```

## Reference03 — Lambda Function

Lambda 함수는 DynamoDB 테이블에서 특정 콘서트의 예매 정보를 쿼리하여 반환합니다. ALB를 통해 호출되며 아래 입출력 형식을 따릅니다. Lambda 함수가 DynamoDB에 연결하기 위해 필요한 값은 함수에 하드코딩되면 안 됩니다.

| Method | Path | Query Parameter | Response |
| --- | --- | --- | --- |
| GET | /reserv-query | concert_name (required) | 예매 정보 목록 |

Request Example: `GET /reserv_query?concert_name=2ND%20TINY_CON`

Response:

```json
[
  {
    "client_id": "C1020",
    "username": "chuu",
    "email": "jiwo@atrp.com",
    "concert_name": "2ND TINY_CON",
    "booking_id": "97E53A10",
    "created_at": "2026-04-25T16:42:45+09:00"
  }
]
```

- created_at 값의 시간대는 KST를 사용합니다.
- Lambda 함수 입출력 형식은 ALB 포맷을 따릅니다.
- concert_name 파라미터가 없는 경우 400 Bad Request를 반환합니다.
- 조회 결과는 데이터베이스 레벨에서 최신순으로 정렬되어 반환되어야 합니다.
- 조회 결과가 없는 경우 빈 배열 `[]`과 200 OK를 반환합니다.
