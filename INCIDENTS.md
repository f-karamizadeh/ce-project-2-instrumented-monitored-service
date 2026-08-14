# Incident Reports and Debugging

## Incident #1 - Dashboard Deploy Failed

**Error:**
```
InvalidParameterInput: ... Should be array, not object
Should NOT have additional properties: {"period": 10}
```

**Location:** `dashboard.json` widget Disk %

**Before (broken):**
```json
"metrics": [
  {
    "expression": "SEARCH('{CWAgent,InstanceId,device,fstype,path} MetricName=\"disk_used_percent\" AND InstanceId=\"${instance_id}\"', 'Average', 10)",
    "id": "e1"
  }
],
"period": 10
```

**After (fixed):**
```json
"metrics": [
  [
    {
      "expression": "SEARCH('{CWAgent,InstanceId,device,fstype,path} MetricName=\"disk_used_percent\" AND InstanceId=\"${instance_id}\"', 'Average', 60)",
      "id": "e1",
      "label": "Disk / %"
    }
  ]
],
"period": 60
```

**Root cause:** Dashboard API expects `metrics` as Array of Array. Expression must be wrapped in inner array. Also High-Res period 10 is invalid unless CWAgent interval is 10. Changed to 60.

---

## Incident #2 - Logs Insights Missing level, correlation_id

**Symptom:** In CloudWatch Logs Insights, query `fields level, correlation_id` returned nothing. Discovered fields = 11. Logs looked like:
```
91.0.60.169 - - [13/Aug/2026:11:13:23 +0000] "POST /orders HTTP/1.1" 201 171 "-" "curl/8.14.1"
91.0.58.40 - - [12/Aug/2026:15:47:15 +0000] "GET /health HTTP/1.1" 200 32
```

**Investigation:**
```bash
cat /home/ec2-user/app/app.log | head -n 10
# -> [INFO] Starting gunicorn + access logs
cat /home/ec2-user/app/app.log | grep request_completed -> empty
ps aux | grep gunicorn
# -> gunicorn --access-logfile /home/ec2-user/app/app.log --error-logfile /home/ec2-user/app/app.log app:app
sudo cat /etc/systemd/system/myapp.service
# -> same, both logs to same file
journalctl -u myapp -n 30
# -> {"correlation_id": "51e9ef29...", "method":"POST", "path":"/orders", "status_code":201, "latency_ms":41, "level":"INFO", "event":"request_completed"}
# JSON was in journal, not in app.log!
```

**Root cause:** `myapp.service` configured both access and error log to same file `app.log`. Gunicorn access logs polluted the file. Structlog writes to stdout, which systemd sends to journal by default, not to app.log.

**Fix:**
```ini
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
```

Commands:
```bash
sudo tee /etc/systemd/system/myapp.service > /dev/null <<'EOF'
...
EOF
sudo systemctl daemon-reload
sudo systemctl restart myapp
> /home/ec2-user/app/app.log
curl -s -X POST http://127.0.0.1:5000/orders -H "Content-Type: application/json" -d '{"amount":150}'
cat /home/ec2-user/app/app.log
# -> {"event":"order_created",...} {"event":"request_completed","level":"INFO","correlation_id":"..."}
```

**Result:** After fix, `app.log` contains only JSON, Logs Insights shows `level`, `correlation_id`, `latency_ms`, `method`, `path`, etc.

---

## Incident #3 - Metrics Not Visible From EC2

**Commands:**
```bash
aws cloudwatch put-metric-data --namespace "Proj2/MyApp" --metric-name "test" --value 1 --region us-east-1
# -> OK, no error

aws cloudwatch list-metrics --namespace "Proj2/MyApp" --region us-east-1
# -> AccessDenied: User arn:aws:sts::204146947593:assumed-role/proj2-ec2-role/i-01b042962afdf4a30 is not authorized to perform: cloudwatch:ListMetrics

aws sts get-caller-identity
# -> assumed-role/proj2-ec2-role/i-01b042962afdf4a30

aws iam list-attached-role-policies --role-name proj2-ec2-role
# -> AccessDenied iam:ListAttachedRolePolicies
```

**Root cause:** Role `proj2-ec2-role` had `PutMetricData` permission (so put worked) but lacked `ListMetrics`, `GetMetricStatistics`, and `iam:ListPolicies`. Also typo: `ws cloudwatch` -> `aws`.

**Fix:** Add to IAM policy:
- `cloudwatch:PutMetricData`
- `cloudwatch:ListMetrics`, `GetMetricStatistics`
- `logs:CreateLogGroup`, `CreateLogStream`, `PutLogEvents`

Test `list-metrics` from laptop with Admin profile, not from EC2 role.

---

## Incident #4 - Typo and Service Name Confusion

- `ws cloudwatch put-metric-data` -> `-bash: ws: command not found` (should be `aws`)
- `sudo cat /etc/systemd/system/app.service` -> No such file, actual name `myapp.service`
- `cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` -> No such file, actual location `/etc/amazon/amazon-cloudwatch-agent/` or `/opt/.../amazon-cloudwatch-agent.d/`

---

## Timeline
- Aug 12 15:43:52 - First gunicorn start, logs only Apache
- Aug 12-13 - Dashboard deploy fails with SEARCH array error
- Aug 13 11:13:18-11:13:23 - Orders created, JSON goes to journal, Apache to app.log
- Aug 13 12:55-12:58 - Restarts, curl tests, discovery that grep request_completed is empty in app.log but present in journalctl
- Final fix: Separate access.log, StandardOutput append to app.log

#  High Error Rate & High Latency
- Trigger: 20x /fail
- Observed: error_count Sum > 5 in 1 min
- Alarm: proj2-high-error -> Fired, email received at 15:40 UTC
- Logs: correlation_id xyz found 5 ERROR logs
- Mitigation: Restart gunicorn (systemctl restart myapp)

