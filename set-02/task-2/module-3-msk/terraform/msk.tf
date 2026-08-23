# ---------------------------------------------------------------------------
# MSK (과제지 2. MSK — mark 3-3: 이름/ACTIVE/3.6.0/kafka.t3.small/IAM=True)
# - 프라이빗 서브넷 2AZ. IAM 인증은 항상 켠다(mark 3-3: Sasl.Iam.Enabled=True).
#   기본 producer_auth_mode=iam 은 unauthenticated=false 로 IAM 전용 — 과제지 "IAM 인증을
#   통해서만 접근" 요구값이다. tls 모드에서만 비인증 TLS(9094)를 추가로 연다: 제공 producer
#   바이너리는 IAM signer 가 없어 9094 로만 붙는다(로컬 실행 테스트로 확정). 기능 확인용 예외다.
# - 브로커 2대: RF 2 토픽을 지지하는 최소 고가용성 구성 (~30분 생성 소요).
#   토픽은 producer user_data 가 kafka-topics.sh 로 만들고, mark 3-3 은 그 메타데이터를
#   MSK 컨트롤플레인 API(aws kafka list-topics)로 조회한다
# ---------------------------------------------------------------------------

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = length(var.broker_subnet_names)

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = [for name in var.broker_subnet_names : aws_subnet.this[name].id]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
    unauthenticated = var.producer_auth_mode == "tls"
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
}

locals {
  # kafka-cluster IAM 액션용 토픽/그룹 ARN (cluster/<name>/<uuid> → topic|group/...)
  topic_arn_prefix = replace(aws_msk_cluster.this.arn, ":cluster/", ":topic/")
  group_arn_prefix = replace(aws_msk_cluster.this.arn, ":cluster/", ":group/")
  raw_topic_arn    = "${local.topic_arn_prefix}/${var.topic_raw.name}"
  alert_topic_arn  = "${local.topic_arn_prefix}/${var.topic_alert.name}"
  any_group_arn    = "${local.group_arn_prefix}/*"
}
