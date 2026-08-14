# Monitoring, Logs and Dashboard

## Log Group
- **Name:** `proj2-logs`
- **Source file (after fix):** `/home/ec2-user/app/app.log` - contains ONLY JSON (structlog)
- **Separated files:** `/home/ec2-user/app/access.log` (gunicorn access) and `/home/ec2-user/app/gunicorn-error.log`
- **Retention:** 7 days recommended

### Why logs were broken before
Before the fix, `myapp.service` had:
```
--access-logfile /home/ec2-user/app/app.log --error-logfile /home/ec2-user/app/app.log
```
- Access logs (Apache format: `91.0.60.169 - - [13/Aug...] "POST /orders" 201`) were mixed into `app.log`
- JSON logs from `structlog` went to `journalctl -u myapp`, not to `app.log`
- Result: CloudWatch Logs Insights Discovered fields = 11, no `level`, `correlation_id`, `latency_ms`

After fix with `StandardOutput=append:/home/ec2-user/app/app.log`, `app.log` contains only JSON.

## CloudWatch Agent Config
```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/ec2-user/app/app.log",
            "log_group_name": "proj2-logs",
            "log_stream_name": "{instance_id}-app",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 },
      "disk": { "measurement": ["used_percent"], "metrics_collection_interval": 60, "resources": ["/"] }
    }
  }
}
```

## Dashboard - proj2-dashboard
Fixed file: `dashboard.json`

### Previous bugs fixed:
1. **SEARCH widget:** Must be `metrics: [[{expression}]]` not `[{expression}]`. Error: `Should be array, not object`
2. **Period:** Changed from 10s High-Res to 60s. Error: `Should NOT have additional properties: {"period": 10}`

### Widgets
- **Top SingleValue:** request_count, error_count, api_latency, orders_per_minute
- **Golden Signals:** Traffic, Errors, Latency Avg+Max, Saturation CPU+Orders
- **EC2 Resources:** CPU %, Memory % (CWAgent), Network, Disk % via SEARCH
- **Correlation View:** Latency vs Traffic vs Errors vs CPU

### Deploy
```bash
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
sed "s/\${instance_id}/$INSTANCE_ID/g" dashboard.json > dashboard-final.json
aws cloudwatch put-dashboard --dashboard-name proj2-dashboard --dashboard-body file://dashboard-final.json --region us-east-1
```

## Logs Insights Queries

### Validate JSON fields
```sql
fields @timestamp, level, correlation_id, method, path, status_code, latency_ms, event, order_id, amount
| filter event="request_completed"
| sort @timestamp desc
| limit 20
```

### Error rate
```sql
fields @timestamp, correlation_id, path, status_code
| filter status_code >= 400
| stats count() as errors by bin(1m)
```

### Latency
```sql
fields latency_ms, correlation_id
| filter event="request_completed"
| stats avg(latency_ms) as avg_ms, max(latency_ms), pct(latency_ms,95) as p95 by bin(1m)
```

### Business
```sql
fields amount, order_id, correlation_id
| filter event="order_created"
| stats sum(amount) as revenue, count() as orders by bin(1m)
```

## Metrics
- Namespace: Proj2/MyApp - request_count, api_latency, error_count, orders_per_minute, order_value
- Test: `aws cloudwatch put-metric-data --namespace Proj2/MyApp --metric-name test --value 1 --region us-east-1` from EC2, `list-metrics` from Admin console (role lacked ListMetrics permission, hence AccessDenied from EC2)

## IAM Policy Required
PutMetricData, ListMetrics, GetMetricStatistics, logs:CreateLogGroup, CreateLogStream, PutLogEvents

## Validation
- cat app.log shows JSON not Apache
- ps aux shows --access-logfile /home/ec2-user/app/access.log
- Discovered fields >20 including level, correlation_id, latency_ms
