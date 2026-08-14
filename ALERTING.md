# Alarms and failure testing

## Test scenario with /fail
Endpoint `/fail` returns 500 with a 50% probability. For alarm testing.

```bash
for i in {1..20}; do curl -s http://127.0.0.1:5000/fail; echo; sleep 1; done
```

## CloudWatch Alarms 

### 1. High Error Rate
```bash
aws cloudwatch put-metric-alarm --alarm-name proj2-high-error-rate \
--alarm-description "Error count >5 in 2 minutes" \
--namespace Proj2/MyApp --metric-name error_count \
--statistic Sum --period 60 --evaluation-periods 2 --threshold 5 \
--comparison-operator GreaterThanThreshold --region us-east-1
```

### 2. High Latency
```bash
aws cloudwatch put-metric-alarm --alarm-name proj2-high-latency \
--namespace Proj2/MyApp --metric-name api_latency \
--statistic Average --period 60 --evaluation-periods 2 --threshold 500 \
--comparison-operator GreaterThanThreshold --unit Milliseconds \
--region us-east-1
```

### 3. EC2 High Memory
```bash
aws cloudwatch put-metric-alarm --alarm-name proj2-high-mem \
--namespace Proj2/MyApp --metric-name mem_used_percent \
--statistic Sum --period 300 --evaluation-periods 1 --threshold 1 \
--comparison-operator LessThanThreshold \
--treat-missing-data breaching --region us-east-1
```

### 4. EC2 High Disk
```bash
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws cloudwatch put-metric-alarm --alarm-name proj2-high-disk \
--namespace AWS/EC2 --metric-name disk_used_percent \
--dimensions Name=InstanceId,Value=$INSTANCE_ID \
--statistic Average --period 300 --evaluation-periods 2 --threshold 80 \
--comparison-operator GreaterThanThreshold --region us-east-1
```
### 5. EC2  Memory Anomaly
```bash
aws cloudwatch put-metric-alarm --alarm-name proj2-mem-use-anomaly-detection \
--namespace Proj2/MyApp --metric-name mem_used_percent \
--statistic Sum --period 300 --evaluation-periods 1 --threshold 1 \
--comparison-operator GreaterThanUpperThreshold \
--treat-missing-data breaching --region us-east-1 \
--Expression ANOMALY_DETECTION_BAND(m1, 2)
```

## تست Incident

1. `systemctl stop myapp` -> expected alarm no-traffic 
2. `for i in {1..50}; do curl .../fail; done` -> error_count alarm
3. Check Logs Insights for correlation_id errors:
```sql
fields @timestamp, correlation_id, path, status_code, level
| filter status_code >= 500
| sort @timestamp desc
```

## Notification (SNS)
```bash
aws sns create-topic --name proj2-alerts --region us-east-1
aws cloudwatch put-metric-alarm ... --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:proj2-alerts
```

