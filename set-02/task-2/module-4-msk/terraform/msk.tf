# ---------------------------------------------------------------------------
# MSK (과제지 2. MSK — mark 4-3: 이름/ACTIVE/3.6.0/kafka.t3.small/IAM=True)
# - 프라이빗 서브넷 2AZ, IAM 인증 전용 (unauthenticated = false)
# - 브로커 2대: RF 2 토픽을 지지하는 최소 고가용성 구성 (~30분 생성 소요)
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
    unauthenticated = false
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
