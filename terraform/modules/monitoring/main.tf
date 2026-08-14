variable "alert_email" {
  type        = string
  description = "Email for CloudWatch alarms"
}

data "aws_instance" "app" {
  filter {
    name   = "tag:Name"
    values = ["proj2-app-server"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# --- SNS ---
resource "aws_sns_topic" "alerts" {
  name = "proj2-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Alarms for App Metrics (Proj2/MyApp) ---
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "proj2-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "api_latency"
  namespace           = "Proj2/MyApp"
  period              = 60
  statistic           = "Average"
  threshold           = 500
  alarm_description   = "Avg API latency > 500ms"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_error" {
  alarm_name          = "proj2-high-error"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "error_count"
  namespace           = "Proj2/MyApp"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Errors > 5 per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Alarms for CWAgent (Fixed for High-Res 10s) ---
resource "aws_cloudwatch_metric_alarm" "high_mem" {
  alarm_name          = "proj2-high-mem"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Memory > 80%"
  dimensions = {
    InstanceId = data.aws_instance.app.id
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_disk" {
  alarm_name          = "proj2-high-disk"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Disk / > 80%"
  dimensions = {
    InstanceId = data.aws_instance.app.id
    path       = "/"
    fstype     = "xfs"
    device     = "nvme0n1p1"
  }
  # اگر fstype/device تو کنسول فرق داشت، از پایین ببین و عوض کن:
  # برو CloudWatch > Metrics > CWAgent > disk_used_percent > Dimensions رو چک کن
  # معمولا ext4 یا xfs و device = /dev/nvme0n1p1 یا nvme0n1p1
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# --- Dashboard (reads from external json file) ---
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "proj2-dashboard"
  dashboard_body = templatefile("${path.module}/dashboard.json", {
    instance_id = data.aws_instance.app.id
  })
}
