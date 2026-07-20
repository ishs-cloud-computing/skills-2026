---
title: "설계 개요"
sidebar:
  order: -1
---

EKS(Bottlerocket) 위에 Book API를 배포하고, CloudFront 단일 엔드포인트로 S3 정적 페이지 · ALB API · Lambda 조회 API · Grafana를 함께 서비스하는 과제. 전 리소스 `ap-northeast-2`(WAF Web ACL만 AWS 제약상 예외, §3.10). **NAT 없음 / Private Subnet 2개뿐**이라는 제약이 설계 전반을 지배한다.
