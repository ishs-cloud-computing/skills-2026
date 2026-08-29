# 제1과제 채점기준

원본은 `mark.pdf`, 실행 스크립트는 `mark.sh`. 아래는 텍스트 추출본.

## 채점상의 유의사항

1. AWS 리전은 `ap-northeast-2`를 사용한다.
2. 웹페이지 접근은 크롬/파이어폭스를 이용한다.
3. 웹페이지에서 언어에 따라 문구가 다르게 보일 수 있다.
4. shell 명령어 출력은 버전에 따라 조금 다를 수 있다.
5. 문제지·채점지의 `<>`는 변수이며 해당 부분을 변경해 입력한다.
6. 채점은 문항 순서대로 진행한다.
7. 삭제된 채점자료는 되돌릴 수 없다.
8. 부분 점수가 있는 문항은 채점 항목에 부분 점수가 적혀 있다.
9. 부분 점수가 따로 없는 문항은 모두 맞아야 점수로 인정된다.
10. 리소스 정보를 읽는 항목은 기본적으로 스크립트 결과로 채점한다.
11. (예상 출력)은 바로 이전 (명령어 입력)의 예상 출력이다.
12. 채점 시 별도 제공한 `mark.sh`를 실행하여 채점할 수 있다.
13. `mark.sh`는 CloudShell 최상위 경로에 위치시킨다.
14. **모든 채점은 CloudShell에서 진행한다.**

## 배점 (총 30점)

| # | 주요항목 | 배점 | 세부항목 | 배점 |
|---|---|---|---|---|
| 1 | Network Configuration | 3.0 | 1-1 VPC / 1-2 Route Table / 1-3 NAT Gateway | 1.0 / 1.0 / 1.0 |
| 2 | Container Registry | 2.5 | 2-1 ECR Repository / 2-2 ECR Image Size | 1.0 / 1.5 |
| 3 | Database | 2.5 | 3-1 DynamoDB Configuration / 3-2 DynamoDB Encryption / 3-3 DynamoDB Access Restrictions | 1.0 / 0.5 / 1.0 |
| 4 | Container | 6.5 | 4-1 EKS Configuration / 4-2 NodeGroup Configuration / 4-3 Node Naming Convention / 4-4 Application Pods / 4-5 Network Policy | 1.0 / 1.5 / 1.5 / 1.0 / 1.5 |
| 5 | Load Balancing | 1.0 | 5-1 ALB Configuration | 1.0 |
| 6 | Static Web Hosting | 2.0 | 6-1 S3 Object Existence / 6-2 S3 Encryption | 1.0 / 1.0 |
| 7 | Lambda | 1.0 | 7-1 Lambda Configuration | 1.0 |
| 8 | CDN | 5.5 | 8-1 S3 Static Content / 8-2 ALB API / 8-3 Lambda API 1 / 8-4 Lambda API 2 | 1.0 / 1.5 / 1.5 / 1.5 |
| 9 | WAF | 3.0 | 9-1 HTTP Method Restriction / 9-2 Query String Restriction | 1.5 / 1.5 |
| 10 | Monitoring | 3.0 | 10-1 Fluent Bit / 10-2 Grafana Dashboard | 1.5 / 1.5 |

## 사전준비

```bash
# CloudShell 접근 후
rm -rf ~/.aws

export DistributionID="<CloudFront_Distribution_ID>"
export BUCKET="gj2026-static-<비번호>"
export CF_DOMAIN=$(aws cloudfront get-distribution --id ${DistributionID} --query "Distribution.DomainName" --output text)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws configure set default.region ap-northeast-2
aws eks update-kubeconfig --name gj2026-eks-cluster
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com

# CDN 캐시 무효화 (최대 3분 대기)
export InvalidationID=$(aws cloudfront create-invalidation --distribution-id ${DistributionID} --paths "/*" --query "Invalidation.Id" --output text)
aws cloudfront wait invalidation-completed --distribution-id ${DistributionID} --id ${InvalidationID}
```

## 채점내용

명령어 원문은 `mark.sh` 참조. 아래는 항목별 **예상 출력**.

### 1-1-A (VPC) — 정확히 일치

```
"10.0.0.0/16"
gj2026-private-subnet-a 10.0.10.0/24    ap-northeast-2a
gj2026-private-subnet-b 10.0.11.0/24    ap-northeast-2b
```

### 1-2-A (Route Table) — 정확히 일치

```
gj2026-private-rtb-a
ROUTES  10.0.0.0/16
gj2026-private-rtb-b
ROUTES  10.0.0.0/16
```

### 1-3-A (NAT Gateway) — 정확히 일치

```
0
gj2026-igw
```

### 2-1-A (ECR Repository) — 정확히 일치

```
book
```

### 2-2-A (ECR Image Size) — 3MB 이하인지 확인

`imageTags[0]==latest` 인 이미지의 `imageSizeInBytes` 기준.

```
2.66mb
```

### 3-1-A (DynamoDB Configuration) — 정확히 일치

```
booking_id
GSI     client_id-index client_id
```

### 3-2-A (DynamoDB Encryption) — 정확히 일치

```
alias/gj2026-db-key
```

### 3-3-A (DynamoDB Access Restrictions) — AccessDenied 출력 확인

CloudShell(관리자 권한)에서 `put-item` 시도.

```
aws: [ERROR]: An error occurred (AccessDeniedException) when calling the PutItem operation: (이하 생략)
```

### 4-1-A (EKS Configuration) — 정확히 일치

```
gj2026-eks-cluster 1.35 ACTIVE True True
alias/gj2026-eks-key
```

### 4-2-A (NodeGroup Configuration) — 정확히 일치

```
gj2026-eks-addon-nodegroup    BOTTLEROCKET_x86_64   t3.medium    2
gj2026-eks-app-nodegroup      BOTTLEROCKET_x86_64   m5.large      2
```

### 4-3-A (Node Naming Convention) — 정확히 일치 (순서 무관)

```
gj2026.<instance-id>.addon.node
gj2026.<instance-id>.addon.node
gj2026.<instance-id>.app.node
gj2026.<instance-id>.app.node
```

### 4-4-A (Application Pods)

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
book   2/2     2            2           21h
```
(AGE는 다를 수 있음)

### 4-5-A (Network Policy) — 정확히 일치

`skills` 네임스페이스에 nginx-test Pod를 띄워 `book-svc:8080/health` 호출.

```
pod/nginx-test created
curl: (28) Connection timed out after 5002 milliseconds
command terminated with exit code 28
```

### 5-1-A (ALB Configuration) — 정확히 일치

```
internal
gj2026-vpc
```

### 6-1-A (S3 Object Existence) — 정확히 일치

```
index.html      main.jpeg
```

### 6-2-A (S3 Encryption) — 정확히 일치

```
alias/gj2026-s3-key
```

### 7-1-A (Lambda Configuration) — 정확히 일치

```
gj2026-book-reservation python3.14 Active
```

### 8-1-A (S3 Static Content) — 정확히 일치

```
200 Miss from cloudfront
200 Miss from cloudfront
200 Hit from cloudfront
```
(순서: `/`, `/main.jpeg`, `/index.html`)

### 8-2-A (ALB API)

```
{"booking_id":"K16MBR45"}
{"booking_id":"OCYGWYIO"}
```
(booking_id 값은 다를 수 있음)

### 8-3-A (Lambda API 1) — 정확히 일치 (순서 무관)

`date` 출력 시각을 10-2 채점을 위해 기록한다.

```
[{"username": "Bob", "email": "han@example.com", "concert_name": "Seoul2025"}, {"username": "Alice", "email": "kim@example.com", "concert_name": "Busan2025"}]
```

### 8-4-A (Lambda API 2) — 정확히 일치

```
[{"username": "Alice", "email": "kim@example.com", "concert_name": "Busan2025"}]
```

### 9-1-A (HTTP Method Restriction) — 정확히 일치

```
Method Not Allowed 405
```

### 9-2-A (Query String Restriction) — 정확히 일치

`client_id=123abc`, `client_id=C^001`, `client_id=홍길동` 세 요청 모두:

```
Access Denied 403
```

### 10-1-A (Fluent Bit)

로그 그룹 삭제 → DaemonSet 재시작 → POST 10회 → 스트림별 첫 이벤트의 `remote_addr` 확인.

```
(stream: /book-svc/ap-northeast-2a ip: 10.0.10.66)
(stream: /book-svc/ap-northeast-2b ip: 10.0.11.234)
```
(IP는 다를 수 있음)

### 10-2-A (Grafana Dashboard) — 수동 채점

`${CF_DOMAIN}/grafana`로 브라우저 접근, `admin` / `Skills53#` 로그인.
**WSI Dashboard**의 **Query Count Panel**(Time series)에 `ALL`, `C001` 두 시리즈가 8-3 실행 시각에 각각 1개씩 찍혀야 한다. (최대 3분 대기)
