resource "aws_sns_topic" "alerts" {
  name = "proj2-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

variable "alert_email" { type = string }
output "sns_arn" { value = aws_sns_topic.alerts.arn }