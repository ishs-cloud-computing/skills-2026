# 2026년도 전국기능경기대회 채점기준

**직종명**: 클라우드컴퓨팅

## 1. 채점상의 유의사항

1. 본 채점은 ap-northeast-2 리전을 기준으로 진행한다.
2. 웹 페이지 접근은 Chrome 또는 Firefox로 진행한다.
3. Shell 명령어의 출력은 AWS CLI 버전에 따라 일부 다를 수 있다.
4. 문제지와 채점지에 있는 `<비번호>`, `<자율>` 등은 선수 제출 값으로 확인한다.
5. 채점은 문항 순서대로 진행한다.
6. 부분 점수가 있는 문항은 채점 항목에 표시된 배점만 인정한다.
7. 부분 점수가 따로 없는 문항은 조건을 모두 만족해야 점수로 인정한다.
8. 리소스 정보를 읽어오는 항목은 CloudShell에서 자동화 채점 스크립트로 확인한다.
9. 자동화 채점 스크립트는 항목별 판정에 필요한 AWS CLI, curl 출력값을 생성한다. 채점위원은 채점기준표의 각 항목 판정 기준에 따라 출력값을 확인하여 배점을 부여한다.
10. 선수 이의가 있는 경우 채점위원이 동일 명령을 직접 실행하여 확인할 수 있다.
11. 자동화 채점 스크립트는 리소스를 삭제하거나 수정하지 않는다. 단, Book API 기능 검증 항목은 채점용 데이터를 1건 생성할 수 있다.
12. IAM User Access Key를 별도로 생성하여 채점하지 않는다.
13. CloudShell을 실행한 IAM User 또는 Role 권한으로 채점한다.
14. 채점 시 대기가 필요한 경우 항목당 최대 3분을 초과하지 않는다.
15. 다른 리전의 리소스를 사용한 경우 해당 리소스 관련 항목은 0점 처리한다.
16. Fargate가 아닌 ECS EC2, EKS, EC2 직접 실행 등으로 애플리케이션을 구동한 경우 ECS/Fargate 관련 항목은 0점 처리한다.
17. DynamoDB가 아닌 다른 데이터베이스를 사용한 경우 DynamoDB 관련 항목은 0점 처리한다.
18. CloudFront 단일 엔드포인트가 아닌 S3 URL 또는 ALB URL을 최종 사용자 접근 경로로 제출한 경우 관련 항목은 0점 처리한다.

## 2. 채점기준표

### 1) 주요항목별 배점

| 과제번호 | 일련번호 | 주요항목 | 배점 | 채점방법(독립) | 채점방법(합의) | 채점시기(경기 진행중) | 채점시기(경기 종료후) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 제1과제 | 1 | VPC 및 네트워킹 구성 | 5 | O | | | O |
| | 2 | S3 및 CloudFront 구성 | 5 | O | | | O |
| | 3 | ALB 및 Origin 검증 구성 | 4 | O | | | O |
| | 4 | ECR 및 ECS Fargate 구성 | 6 | O | | | O |
| | 5 | DynamoDB, KMS, IAM 구성 | 5 | O | | | O |
| | 6 | CloudWatch 구성 | 5 | O | | | O |
| | | **합계** | **30** | | | | |

### 2) 채점방법 및 기준

| 과제번호 | 일련번호 | 주요항목 | 세부 일련번호 | 세부항목(채점방법) | 배점 |
| --- | --- | --- | --- | --- | --- |
| 제1과제 | 1 | VPC 및 네트워킹 구성 | 1 | VPC | 1.0 |
| | | | 2 | Public/Private Subnet | 1.0 |
| | | | 3 | Public Routing | 1.0 |
| | | | 4 | NAT Gateway / VPC Endpoint | 1.0 |
| | | | 5 | DynamoDB VPC Endpoint | 1.0 |
| | 2 | S3 및 CloudFront 구성 | 1 | S3, CloudFront | 1.5 |
| | | | 2 | S3 Public Access 차단 | 1.0 |
| | | | 3 | CloudFront OAC | 1.5 |
| | | | 4 | CloudFront 단일 엔드포인트 및 라우팅 | 1.0 |
| | 3 | ALB 및 Origin 검증 구성 | 1 | ALB, Target Group | 1.5 |
| | | | 2 | CloudFront Custom Header | 1.0 |
| | | | 3 | ALB Header 기반 차단 | 1.5 |
| | 4 | ECR 및 ECS Fargate 구성 | 1 | ECR Repository 및 Image | 1.5 |
| | | | 2 | ECS Task Definition | 1.5 |
| | | | 3 | ECS Service | 1.5 |
| | | | 4 | Book API 동작 | 1.5 |
| | 5 | DynamoDB, KMS, IAM 구성 | 1 | DynamoDB Table | 1.0 |
| | | | 2 | DynamoDB KMS CMK | 1.5 |
| | | | 3 | ECS Task Execution Role | 1.0 |
| | | | 4 | ECS Task Role | 1.5 |
| | 6 | CloudWatch 구성 | 1 | ECS Container Logs | 1.5 |
| | | | 2 | 4xx/5xx Metric Filter | 1.5 |
| | | | 3 | CloudWatch Alarm | 1.5 |
| | | | 4 | CloudWatch Alarm 세부 구성 | 0.5 |
| | | | | **합계** | **30** |

### 3) 채점 내용

#### 0. 채점 준비 (배점 없음)

1) 아래 명령어를 입력하여 채점에 필요한 값을 변수로 선언합니다.
2) `<선수비번호>`에는 선수 비번호를 입력합니다. 그 외 값이 비어 있거나 None이면 해당 리소스가 요구 이름으로 생성되지 않은 것입니다.
3) 본 항목은 채점 준비 절차이며 배점은 없습니다.

```bash
export BIBUNHO=<선수비번호>
export S3_BUCKET="skills-book-static-2026-${BIBUNHO}"
export VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-2 --filters Name=tag:Name,Values=skills-book-vpc --query "Vpcs[0].VpcId" --output text)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(join(',', Origins.Items[].DomainName), '${S3_BUCKET}')].Id | [0]" --output text)
export CLOUDFRONT_DOMAIN_NAME=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query "Distribution.DomainName" --output text)
export ALB_DNS_NAME=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query "DistributionConfig.Origins.Items[?contains(DomainName, 'elb.amazonaws.com')].DomainName | [0]" --output text)
export ALB_ARN=$(aws elbv2 describe-load-balancers --region ap-northeast-2 --query "LoadBalancers[?DNSName=='${ALB_DNS_NAME}'].LoadBalancerArn | [0]" --output text)
export TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --region ap-northeast-2 --query "TargetGroups[?contains(LoadBalancerArns, '${ALB_ARN}')].TargetGroupArn | [0]" --output text)
export ECR_REPOSITORY_NAME=$(aws resourcegroupstaggingapi get-resources --region ap-northeast-2 --tag-filters Key=Name,Values=skills-book-ecr --query "ResourceTagMappingList[0].ResourceARN" --output text | awk -F/ '{print $NF}')
export CLUSTER_ARN=$(aws resourcegroupstaggingapi get-resources --region ap-northeast-2 --tag-filters Key=Name,Values=skills-book-cluster --query "ResourceTagMappingList[0].ResourceARN" --output text)
export SERVICE_ARN=$(aws resourcegroupstaggingapi get-resources --region ap-northeast-2 --tag-filters Key=Name,Values=skills-book-service --query "ResourceTagMappingList[0].ResourceARN" --output text)
export CLOUDFRONT_CUSTOM_HEADER_VALUE=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query "DistributionConfig.Origins.Items[].CustomHeaders.Items[?HeaderName=='X-Origin-Verify'].HeaderValue | [0]" --output text)
```

#### 1-1. VPC (배점 1.0)

1) CloudShell에서 아래 명령어를 입력합니다.
2) `skills-book-vpc` VPC가 출력되고 DNS 옵션이 true인지 확인합니다.

```bash
aws ec2 describe-vpcs --region ap-northeast-2 --filters Name=tag:Name,Values=skills-book-vpc --output table
aws ec2 describe-vpc-attribute --region ap-northeast-2 --vpc-id "$VPC_ID" --attribute enableDnsHostnames
aws ec2 describe-vpc-attribute --region ap-northeast-2 --vpc-id "$VPC_ID" --attribute enableDnsSupport
```

#### 1-2. Public/Private Subnet (배점 1.0)

1) 아래 명령어를 입력합니다.
2) `skills-book-vpc` VPC 내 Subnet이 4개 이상이고 서로 다른 AZ의 Public/Private Subnet 구성이 확인되는지 확인합니다.

```bash
aws ec2 describe-subnets --region ap-northeast-2 --filters Name=vpc-id,Values="$VPC_ID" --output table
```

#### 1-3. Public Routing (배점 1.0)

1) 아래 명령어를 입력합니다.
2) Public Subnet Route Table에 0.0.0.0/0 대상 Internet Gateway 경로가 있는지 확인합니다.

```bash
aws ec2 describe-route-tables --region ap-northeast-2 --filters Name=vpc-id,Values="$VPC_ID" --output json
```

#### 1-4. NAT Gateway / VPC Endpoint (배점 1.0)

1) 아래 명령어를 입력합니다.
2) Private Subnet에서 ECR Pull, CloudWatch Logs 전송, AWS API 호출이 가능하도록 NAT Gateway 또는 필요한 VPC Endpoint가 구성되어 있는지 확인합니다.

```bash
aws ec2 describe-nat-gateways --region ap-northeast-2 --filter Name=vpc-id,Values="$VPC_ID" Name=state,Values=available --output table
aws ec2 describe-vpc-endpoints --region ap-northeast-2 --filters Name=vpc-id,Values="$VPC_ID" --query "VpcEndpoints[].{VpcEndpointId:VpcEndpointId,State:State,Type:VpcEndpointType,ServiceName:ServiceName,SubnetIds:SubnetIds,RouteTableIds:RouteTableIds}" --output table
```

#### 1-5. DynamoDB VPC Endpoint (배점 1.0)

1) 아래 명령어를 입력합니다.
2) Gateway 타입 DynamoDB VPC Endpoint가 있고 Service Name이 `com.amazonaws.ap-northeast-2.dynamodb`인지 확인합니다.

```bash
aws ec2 describe-vpc-endpoints --region ap-northeast-2 --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values=com.amazonaws.ap-northeast-2.dynamodb --query "VpcEndpoints[].{VpcEndpointId:VpcEndpointId,State:State,Type:VpcEndpointType,ServiceName:ServiceName,RouteTableIds:RouteTableIds}" --output table
```

#### 2-1. S3, CloudFront (배점 1.5)

1) 아래 명령어를 입력합니다.
2) S3 Bucket에 index.html, main.jpeg가 존재하고 CloudFront Domain으로 접근 가능한지 확인합니다.

```bash
aws s3api list-objects-v2 --region ap-northeast-2 --bucket "$S3_BUCKET" --query "Contents[].Key" --output table
aws cloudfront list-distributions --query "DistributionList.Items[].{Id:Id,DomainName:DomainName,Origins:Origins.Items[].DomainName}" --output table
curl -I "https://${CLOUDFRONT_DOMAIN_NAME}/index.html"
```

#### 2-2. S3 Public Access 차단 (배점 1.0)

1) 아래 명령어를 입력합니다.
2) Block Public Access 4개 옵션이 모두 true이고 S3 직접 접근이 200 응답을 반환하지 않는지 확인합니다.

```bash
aws s3api get-public-access-block --region ap-northeast-2 --bucket "$S3_BUCKET"
curl -I "https://${S3_BUCKET}.s3.ap-northeast-2.amazonaws.com/index.html"
```

#### 2-3. CloudFront OAC (배점 1.5)

1) 아래 명령어를 입력합니다.
2) CloudFront Origin Access Control이 연결되어 있고 Bucket Policy가 CloudFront Distribution으로 제한되는지 확인합니다.

```bash
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query "DistributionConfig.Origins.Items[].OriginAccessControlId" --output table
aws s3api get-bucket-policy --region ap-northeast-2 --bucket "$S3_BUCKET" --query Policy --output text
```

#### 2-4. CloudFront 단일 엔드포인트 및 라우팅 (배점 1.0)

1) 아래 명령어를 입력합니다.
2) Default Cache Behavior는 S3 Origin, `/v1/*` Ordered Cache Behavior는 ALB Origin이며 POST가 허용되는지 확인합니다.

```bash
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query "DistributionConfig.{Default:DefaultCacheBehavior,Ordered:CacheBehaviors.Items}" --output json
```

#### 3-1. ALB, Target Group (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Internet-facing ALB와 Target Group이 존재하고 Target Type ip, Port 8080, Health Check `/health`, Healthy Target이 확인되는지 확인합니다.

```bash
aws elbv2 describe-load-balancers --region ap-northeast-2 --output table
aws elbv2 describe-target-groups --region ap-northeast-2 --output table
aws elbv2 describe-target-health --region ap-northeast-2 --target-group-arn "$TARGET_GROUP_ARN" --output table
```

#### 3-2. CloudFront Custom Header (배점 1.0)

1) 아래 명령어를 입력합니다.
2) ALB Origin에 `X-Origin-Verify` Custom Header가 있고 값이 20자 이상인지 확인합니다.

```bash
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --output json
```

#### 3-3. ALB Header 기반 차단 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) ALB 직접 접근은 403, CloudFront Origin Header를 포함한 `/health` 요청은 200인지 확인합니다.

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://${ALB_DNS_NAME}/health"
curl -s -o /dev/null -w "%{http_code}\n" -H "X-Origin-Verify: ${CLOUDFRONT_CUSTOM_HEADER_VALUE}" "http://${ALB_DNS_NAME}/health"
```

#### 4-1. ECR Repository 및 Image (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Name Tag `skills-book-ecr` ECR Repository가 있고 이미지가 1개 이상인지 확인합니다.

```bash
aws resourcegroupstaggingapi get-resources --region ap-northeast-2 --tag-filters Key=Name,Values=skills-book-ecr --output table
aws ecr describe-images --region ap-northeast-2 --repository-name "$ECR_REPOSITORY_NAME" --query "imageDetails[].imageDigest" --output table
```

#### 4-2. ECS Task Definition (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Task Definition Family, Fargate, awsvpc, CPU/Memory, Container, Port, 환경변수, Log Driver가 요구사항과 일치하는지 확인합니다.

```bash
aws ecs describe-task-definition --region ap-northeast-2 --task-definition skills-book-task --query "taskDefinition.{Family:family,Requires:requiresCompatibilities,NetworkMode:networkMode,Cpu:cpu,Memory:memory,Containers:containerDefinitions}" --output json
```

#### 4-3. ECS Service (배점 1.5)

1) 아래 명령어를 입력합니다.
2) ECS Cluster/Service가 존재하고 Desired Count 2, ALB Target Group 연결, Public IP Disabled, Private Subnet 배치인지 확인합니다.

```bash
aws resourcegroupstaggingapi get-resources --region ap-northeast-2 --tag-filters Key=Name,Values=skills-book-cluster,skills-book-service --output table
aws ecs describe-services --region ap-northeast-2 --cluster "$CLUSTER_ARN" --services "$SERVICE_ARN" --query "services[].{Desired:desiredCount,Running:runningCount,Network:networkConfiguration,LoadBalancers:loadBalancers}" --output json
```

#### 4-4. Book API 동작 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) CloudFront로 `POST /v1/book` 요청 시 booking_id가 반환되고 DynamoDB에서 조회되는지 확인합니다.

```bash
curl -s -X POST "https://${CLOUDFRONT_DOMAIN_NAME}/v1/book" -H "Content-Type: application/json" -d "{\"client_id\":\"judge\",\"username\":\"judge\",\"email\":\"judge@example.com\",\"concert_name\":\"skills\"}"
aws dynamodb scan --region ap-northeast-2 --table-name skills-book-booking --limit 5 --output table
```

#### 5-1. DynamoDB Table (배점 1.0)

1) 아래 명령어를 입력합니다.
2) DynamoDB Table `skills-book-booking`이 존재하고 Partition Key가 `booking_id` String인지 확인합니다.

```bash
aws dynamodb describe-table --region ap-northeast-2 --table-name skills-book-booking --query "Table.{Name:TableName,Status:TableStatus,KeySchema:KeySchema,Attributes:AttributeDefinitions}" --output table
```

#### 5-2. DynamoDB KMS CMK (배점 1.5)

1) 아래 명령어를 입력합니다.
2) KMS Alias `alias/skills-book-ddb`가 존재하고 DynamoDB Table의 SSE KMS Key가 해당 CMK인지 확인합니다.

```bash
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-book-ddb --query "KeyMetadata.{Arn:Arn,KeyManager:KeyManager,Enabled:Enabled}" --output table
aws dynamodb describe-table --region ap-northeast-2 --table-name skills-book-booking --query "Table.SSEDescription" --output table
```

#### 5-3. ECS Task Execution Role (배점 1.0)

1) 아래 명령어를 입력합니다.
2) ECS Task Definition에 Execution Role ARN이 설정되어 있는지 확인합니다.

```bash
aws ecs describe-task-definition --region ap-northeast-2 --task-definition skills-book-task --query "taskDefinition.executionRoleArn" --output text
```

#### 5-4. ECS Task Role (배점 1.5)

1) 아래 명령어를 입력합니다.
2) ECS Task Definition에 Task Role ARN이 설정되어 있고 Execution Role과 서로 다른지 확인합니다.

```bash
aws ecs describe-task-definition --region ap-northeast-2 --task-definition skills-book-task --query "taskDefinition.{ExecutionRole:executionRoleArn,TaskRole:taskRoleArn}" --output table
```

#### 6-1. ECS Container Logs (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Log Group `/ecs/skills-book-app` 및 `book` Prefix Log Stream이 존재하는지 확인합니다.

```bash
aws logs describe-log-groups --region ap-northeast-2 --log-group-name-prefix /ecs/skills-book-app --output table
aws logs describe-log-streams --region ap-northeast-2 --log-group-name /ecs/skills-book-app --log-stream-name-prefix book --output table
```

#### 6-2. 4xx/5xx Metric Filter (배점 1.5)

1) 아래 명령어를 입력합니다.
2) 4xx/5xx Metric Filter 이름, Namespace, Metric Name, Metric Value가 요구사항과 일치하는지 확인합니다.

```bash
aws logs describe-metric-filters --region ap-northeast-2 --log-group-name /ecs/skills-book-app --query "metricFilters[].{Name:filterName,Pattern:filterPattern,Metric:metricTransformations[0].metricName,Namespace:metricTransformations[0].metricNamespace,Value:metricTransformations[0].metricValue}" --output table
```

#### 6-3. CloudWatch Alarm (배점 1.5)

1) 아래 명령어를 입력합니다.
2) 4xx/5xx Alarm의 Metric, Namespace, Statistic, Threshold, Period, Evaluation Periods, Datapoints 조건을 확인합니다.

```bash
aws cloudwatch describe-alarms --region ap-northeast-2 --alarm-names skills-book-4xx-alarm skills-book-5xx-alarm --query "MetricAlarms[].{Name:AlarmName,Metric:MetricName,Namespace:Namespace,Statistic:Statistic,Threshold:Threshold,Period:Period,Evaluation:EvaluationPeriods,Datapoints:DatapointsToAlarm}" --output table
```

#### 6-4. CloudWatch Alarm 세부 구성 (배점 0.5)

1) 아래 명령어를 입력합니다.
2) Alarm 이름이 문제지와 일치하고 Treat Missing Data가 notBreaching인지 확인합니다.

```bash
aws cloudwatch describe-alarms --region ap-northeast-2 --alarm-names skills-book-4xx-alarm skills-book-5xx-alarm --query "MetricAlarms[].{Name:AlarmName,TreatMissingData:TreatMissingData}" --output table
```
