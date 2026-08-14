"""
config.py - Central configuration for Proj2 Flask Observability
Based on real EC2 i-01b042962afdf4a30 setup
"""
import os

# AWS
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
CLOUDWATCH_NAMESPACE = "Proj2/MyApp"
LOG_GROUP_NAME = "proj2-logs"
DASHBOARD_NAME = "proj2-dashboard"
EC2_INSTANCE_ID = os.getenv("INSTANCE_ID", "${instance_id}")  # replaced by deploy.sh

# App
APP_HOST = "0.0.0.0"
APP_PORT = 5000
WORKERS = 2
APP_LOG_PATH = "/home/ec2-user/app/app.log"
ACCESS_LOG_PATH = "/home/ec2-user/app/access.log"
ERROR_LOG_PATH = "/home/ec2-user/app/gunicorn-error.log"

# Metrics
METRICS = {
    "request_count": {"unit": "Count", "description": "Total requests"},
    "api_latency": {"unit": "Milliseconds", "description": "Request latency"},
    "error_count": {"unit": "Count", "description": "4xx/5xx errors"},
    "orders_per_minute": {"unit": "Count", "description": "Business orders"},
    "order_value": {"unit": "None", "description": "Order amount"},
}

# Logging - structlog JSON fields expected in Logs Insights
LOG_FIELDS = ["timestamp", "level", "correlation_id", "method", "path", "status_code", "latency_ms", "event", "order_id", "amount"]

# CWAgent
CWAGENT_CONFIG_PATHS = [
    "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json",
    "/etc/amazon/amazon-cloudwatch-agent/amazon-cloudwatch-agent.json",
    "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d/"
]

# Alarms thresholds
ALARMS = {
    "high_error_rate": {"threshold": 5, "period": 60, "eval_periods": 2, "stat": "Sum"},
    "high_latency": {"threshold": 500, "period": 60, "eval_periods": 2, "stat": "Average"},
    "no_traffic": {"threshold": 1, "period": 300, "eval_periods": 1, "stat": "Sum"},
    "high_cpu": {"threshold": 80, "period": 300, "eval_periods": 2, "stat": "Average"},
}
