# Deployment Guide - Proj2 Flask App on EC2

## Prerequisites
- EC2: Amazon Linux 2/2023, t3.micro, role `proj2-ec2-role` with PutMetricData, logs:PutLogEvents
- Security Group: 5000 open for test, 22 for SSH
- Python 3.9+, pip, venv
- Gunicorn 21.2.0
- CloudWatch Agent installed

## Step 1: App Setup
```bash
cd /home/ec2-user/app
python3 -m venv venv
source venv/bin/activate
pip install flask structlog boto3 gunicorn
# app.py must use structlog JSONRenderer and send_metric with try/except
```

## Step 2: Systemd Service (Critical Fix)
Previous broken service:
```
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --access-logfile /home/ec2-user/app/app.log --error-logfile /home/ec2-user/app/app.log app:app
```
This caused Apache logs mixed into app.log and JSON went to journalctl.

**Correct service:**
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
sudo systemctl enable myapp
sudo systemctl restart myapp
```

## Step 3: Verify Logs
```bash
> /home/ec2-user/app/app.log
curl -s -X POST http://127.0.0.1:5000/orders -H "Content-Type: application/json" -d '{"amount":150,"item":"test"}'
cat /home/ec2-user/app/app.log
# Expected: {"event":"order_created",...} {"event":"request_completed","level":"INFO","correlation_id":"...","latency_ms":...}
# NOT: 91.0.60.169 - - [13/Aug...] "POST /orders"

# If still Apache, check:
ps aux | grep gunicorn
journalctl -u myapp -n 20 --no-pager
```

## Step 4: CloudWatch Agent
```bash
# Create config file /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d/config.json or /etc/amazon/amazon-cloudwatch-agent/
# See MONITORING.md for JSON
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/path/to/config.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
```

## Step 5: Metrics Test
```bash
aws cloudwatch put-metric-data --namespace "Proj2/MyApp" --metric-name "test" --value 1 --region us-east-1
# From Admin laptop:
aws cloudwatch list-metrics --namespace "Proj2/MyApp" --region us-east-1
```

If AccessDenied ListMetrics from EC2, role needs ListMetrics permission. Put works with only PutMetricData.

## Step 6: Dashboard Deploy
```bash
./deploy.sh
# Or manually:
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
sed "s/\${instance_id}/$INSTANCE_ID/g" dashboard.json > /tmp/dashboard-final.json
aws cloudwatch put-dashboard --dashboard-name proj2-dashboard --dashboard-body file:///tmp/dashboard-final.json --region us-east-1
```

Fix history: dashboard_1..5 had invalid period 10 and SEARCH syntax `metrics: [{expression}]` -> Fixed to `[[{expression}]]` and period 60.

## Step 7: Alarms
See ALERTING.md. Create alarms for error_count, api_latency, request_count, CPUUtilization.

## Common Errors
- `ws cloudwatch` -> typo, should be `aws`
- `/etc/systemd/system/app.service: No such file` -> actual `myapp.service`
- `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json: No such file` -> check `amazon-cloudwatch-agent.d/`
- `Should be array, not object` -> SEARCH widget fix
- `Should NOT have additional properties: {"period": 10}` -> change period to 60
