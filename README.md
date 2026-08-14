# Proj2 - Monitoring and Observability with Dashboard
Author: Faramarz Karamizadeh Aug.2026


## Architecture overview
- **Instance:** `i-01b042962afdf4a30` - `10.0.1.221` - `us-east-1`
- **Role:** `proj2-ec2-role` (STS Assumed)
- **App:** Flask + Gunicorn 21.2.0 (2 workers) - Port 5000
- **Service:** `/etc/systemd/system/myapp.service`
- **Logs:** `/home/ec2-user/app/app.log` (JSON) + `/home/ec2-user/app/access.log` (separate)
- **Metrics Namespace:** `Proj2/MyApp`
- **Log Group:** `proj2-logs` (CloudWatch Logs)
- **Dashboard:** `proj2-dashboard` (CloudWatch Dashboard)

## Endpoints
- `GET /health` -> `{"status":"ok","version":"1.0"}`
- `POST /orders` -> body `{"amount": int, "item": str}` - creates order with `correlation_id`
- `GET /orders` -> list in-memory orders
- `GET /fail` -> 50% injects 500 for alarm testing

## Issues i faced
1.  **Dashboard InvalidParameter:** `metrics: [{"expression": SEARCH(...)}]` should be `[[{expression}]]`  + period 10 -> 60
2.  **Logs:** `gunicorn --access-logfile app.log --error-logfile app.log` Apache Access Log mixed with JSON structlog JSON  `journalctl -u myapp` not `app.log`
3.  **Fix:** `myapp.service` to:
    ```
    --access-logfile /home/ec2-user/app/access.log
    --error-logfile /home/ec2-user/app/gunicorn-error.log
    StandardOutput=append:/home/ec2-user/app/app.log
    StandardError=append:/home/ec2-user/app/app.log
    ```
4.  **IAM:** Role `proj2-ec2-role` has`PutMetricData`  but not `ListMetrics` and `ListAttachedRolePolicies` and it caused EC2 `list-metrics` AccessDenied.

## fast run
```bash
sudo systemctl daemon-reload
sudo systemctl restart myapp
curl -X POST http://127.0.0.1:5000/orders -H "Content-Type: application/json" -d '{"amount":150}'
cat /home/ec2-user/app/app.log
sudo journalctl -u myapp -n 20
```

## test Logs Insights
```sql
SOURCE "arn:aws:logs:us-east-1:204146947593:log-group:proj2-logs" START=-604800s END=0s |
fields @timestamp, level, correlation_id, method, path, status_code, latency_ms, event, order_id, amount
| filter event="request_completed"
| sort @timestamp desc
| limit 20



SOURCE "arn:aws:logs:us-east-1:204146947593:log-group:proj2-logs" START=-604800s END=0s |
fields @timestamp, level, correlation_id, method, path, status_code, latency_ms, event, order_id, amount
| filter correlation_id="02621c3a-7a20-46ea-b6e5-1157ae7a516d"
| sort @timestamp desc
| limit 20
```
