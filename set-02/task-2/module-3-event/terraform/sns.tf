# SNS (과제지 7. SNS — mark 3-1 이 TopicArn 정확 일치 채점)
resource "aws_sns_topic" "alert" {
  name = var.topic_name
}
