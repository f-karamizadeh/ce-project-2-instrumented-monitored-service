# Runbook - Proj2 Incident Response

## Quick Triage

### 1. Service Down - No Traffic Alarm
**Alarm:** `proj2-no-traffic` (request_count <1 for 5m)

**Check:**
```bash
ps aux | grep gunicorn
sudo systemctl status myapp
sudo journalctl -u myapp -n 50 --no-pager
cat /home/ec2-user/app/app.log | tail -n 20
```

**Fix:**
```bash
sudo systemctl restart myapp
# If app.log is polluted with Apache logs:
# Check service file
sudo cat /etc/systemd/system/myapp.service
# Must have:
# --access-logfile /home/ec2-user/app/access.log --error-logfile /home/ec2-user/app/gunicorn-error.log
# StandardOutput=append:/home/ec2-user/app/app.log
sudo systemctl daemon-reload
sudo systemctl restart myapp
```

### 2. High Error Rate - `proj2-high-error-rate`
**Check Logs Insights:**
```sql
fields @timestamp, correlation_id, path, status_code, level, latency_ms
| filter status_code >= 500
| sort @timestamp desc
| limit 20
```

**Test failure injection:**
```bash
curl -s http://127.0.0.1:5000/fail
for i in {1..20}; do curl -s http://127.0.0.1:5000/fail; echo; sleep 0.5; done
```

### 3. High Latency - `proj2-high-latency`
**Query:**
```sql
fields latency_ms, path, correlation_id
| filter event="request_completed"
| stats avg(latency_ms), max(latency_ms), pct(latency_ms,95) by bin(1m), path
| sort avg_latency desc
```

**EC2 check:**
```bash
top
# Check CWAgent metrics
aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) --start-time $(date -u -d '10 min ago' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 60 --statistics Average --region us-east-1
```

### 4. Logs Missing level, correlation_id
This was Incident #2 in this project. Symptom: Discovered fields = 11 only.

**Root cause checklist:**
- `cat /home/ec2-user/app/app.log` shows `91.0.60.169 - - [13/Aug...] "POST /orders"` (Apache) -> BAD
- Should show `{"event":"request_completed","level":"INFO","correlation_id":"..."}`
- `journalctl -u myapp` contains JSON but app.log does not -> StandardOutput not set

**Fix:**
```bash
sudo tee /etc/systemd/system/myapp.service > /dev/null <<'EOF'
[Unit]
Description=My Flask App
After=network.target
[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/app
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --access-logfile /home/ec2-user/app/access.log --error-logfile /home/ec2-user/app/gunicorn-error.log app:app
StandardOutput=append:/home/ec2-user/app/app.log
StandardError=append:/home/ec2-user/app/app.log
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl restart myapp
> /home/ec2-user/app/app.log
curl -X POST http://127.0.0.1:5000/orders -H "Content-Type: application/json" -d '{"amount":100}'
cat /home/ec2-user/app/app.log
```

Wait 1 minute for CWAgent to ship, then Logs Insights query must show level, correlation_id.

### 5. Metrics AccessDenied
```bash
aws sts get-caller-identity
# If arn:aws:sts::...:assumed-role/proj2-ec2-role/i-xxx
# Put works, List fails -> role missing ListMetrics permission
```
Test Put:
```bash
aws cloudwatch put-metric-data --namespace Proj2/MyApp --metric-name test --value 1 --region us-east-1
```
List must be from Admin laptop, not from EC2 role if policy limited.

## Correlation ID Tracing
Every request gets `X-Correlation-ID` or generated uuid. Trace end-to-end:

1. Client: `curl -H "X-Correlation-ID: my-test-123" -X POST .../orders -d '{"amount":200}'`
2. Response contains `correlation_id`
3. Logs Insights:
```sql
fields @timestamp, event, level, path, status_code
| filter correlation_id="my-test-123"
| sort @timestamp asc
```

## Useful Commands
```bash
# All logs location
ls -lh /home/ec2-user/app/*.log
# gunicorn workers
ps aux | grep gunicorn
# real instance id
curl -s http://169.254.169.254/latest/meta-data/instance-id
# disk / memory
df -h
free -m
# cwagent config find
sudo find /etc /opt -name "*cloudwatch*agent*.json" 2>/dev/null
```
