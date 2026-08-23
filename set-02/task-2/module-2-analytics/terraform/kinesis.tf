# ---------------------------------------------------------------------------
# Kinesis Data Stream (과제지 4. Kinesis, mark 2-3: ACTIVE / ON_DEMAND)
# ---------------------------------------------------------------------------

resource "aws_kinesis_stream" "orders" {
  name = var.stream_name

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = { Name = var.stream_name }
}
