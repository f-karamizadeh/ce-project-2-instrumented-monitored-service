Dashboard Hierarchy:
````
┌────────────────────────────────────────────┐
│ WEB TIER HEALTH - Production              │ ← Header
├────────────────────────────────────────────┤
│ 🔴 Active Alerts: 5                        │ ← Critical Info
│ System Status: ⚠️ DEGRADED                │
├────────────────────────────────────────────┤
│ [Request Rate]  │  [Error Rate]            │ ← Golden
│                 │                          │   Signals
│ [Latency P95]   │  [Target Health]         │
├────────────────────────────────────────────┤
│ [CPU]  │ [Memory]  │ [Network]  │ [Disk]  │ ← Resources
├────────────────────────────────────────────┤
│ [Request Rate + Error Rate Correlation]    │ ← Correlation
└────────────────────────────────────────────┘
````
# ARCHITECTURE

## Diagram
```
Client (curl / Browser 91.0.x.x)
   |
   v
EC2 (t3.micro - 10.0.1.221:5000)
   |-- myapp.service (systemd)
   |     └─ gunicorn (2 workers, sync) -> app:app
   |          ├─ structlog JSON -> stdout -> StandardOutput -> /home/ec2-user/app/app.log
   |          ├─ access.log -> /home/ec2-user/app/access.log (separate)
   |          └─ boto3 CloudWatch client -> PutMetricData -> Namespace Proj2/MyApp
   |
   |-- CloudWatch Agent (CWAgent)
   |     └─ tail app.log -> Log Group proj2-logs -> Logs Insights (level, correlation_id)
   |     └─ mem_used_percent, disk_used_percent -> Namespace CWAgent (period 60s)
   |
   └─ AWS/EC2 metrics -> CPUUtilization, NetworkIn/Out -> Namespace AWS/EC2
```

## Components

### 1. App Layer (`app.py`)
- Flask 2.x
- `structlog` with `TimeStamper(fmt="iso")` + `JSONRenderer()`
- `before_request`: `g.correlation_id = X-Correlation-ID header or uuid4`, `g.start_time`
- `after_request`: `latency_ms = (now - start)*1000`, `log.info("request_completed", correlation_id, method, path, status_code, latency_ms, level=...)`
- `send_metric(name, value, unit)`: `cw_client.put_metric_data(Namespace='Proj2/MyApp', MetricData=[... Timestamp=datetime.utcnow()])` with try/except 

### 2. Compute Layer
- **Service file:** `/etc/systemd/system/myapp.service` - `User=ec2-user`, `WorkingDirectory=/home/ec2-user/app`, `Restart=always`
- **Gunicorn args ** `--bind 0.0.0.0:5000 --workers 2 --access-logfile /home/ec2-user/app/access.log --error-logfile /home/ec2-user/app/gunicorn-error.log`
- **Fix :** `StandardOutput=append:/home/ec2-user/app/app.log` and `StandardError=append:...`   JSON from journal to file.

### 3. Observability Layer
- **Logs:** CloudWatch Agent read `app.log` ( JSON).
- **Metrics Custom:** `request_count` (Count), `api_latency` (Milliseconds), `error_count` (Count), `orders_per_minute`, `order_value`
- **Metrics EC2:** `CPUUtilization` (AWS/EC2), `mem_used_percent` (CWAgent), `disk_used_percent` (CWAgent SEARCH), `NetworkIn/Out`

### 4. Dashboard Layer
- `dashboard.json` با widgets: SingleValue (Current Request Rate, Error Rate, Avg Latency, Orders/min) + timeSeries (Golden Signals) + Resource Utilization + Correlation View

## Data Flow
1. Request -> g.correlation_id
2. log.info order_created (business log) + put_metric order_value
3. after_request -> log.info request_completed + put_metric request_count, api_latency, error_count (if >=400)
4. app.log -> CWAgent -> CloudWatch Logs -> Insights query
5. CloudWatch Metrics -> Dashboard
