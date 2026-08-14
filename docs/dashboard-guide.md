# Dashboard Guide - proj2-dashboard

## Overview
Dashboard name: `proj2-dashboard` (us-east-1)
Instance placeholder: `${instance_id}` replaced at deploy time (real id: i-01b042962afdf4a30)

File: `dashboard.json` in repo root. Fixed version period 60s and SEARCH syntax `[[{expression}]]`.

## Widgets Layout

### Row 0: Header
- Text: # Proj2 Health Dashboard (No ALB) | Instance: ${instance_id} | Auto-refresh 60s

### Row 1: Single Value (y=1, height 3)
- **Current Request Rate:** `Proj2/MyApp request_count Sum 60`
- **Error Rate:** `Proj2/MyApp error_count Sum 60` (red)
- **Avg Latency:** `Proj2/MyApp api_latency Average 60`
- **Orders per min:** `Proj2/MyApp orders_per_minute Sum 60`

### Row 2: Golden Signals (y=5)
- **Traffic:** request_count Sum
- **Errors:** error_count Sum red
- **Latency:** api_latency Average + Maximum
- **Saturation:** AWS/EC2 CPUUtilization Average + orders_per_minute Sum (right Y)

### Row 3: EC2 Resources (y=18)
- **CPU %:** AWS/EC2 CPUUtilization InstanceId=${instance_id}
- **Memory % (CWAgent):** CWAgent mem_used_percent InstanceId=${instance_id} Average 60
- **Network:** NetworkIn Sum + NetworkOut Sum
- **Disk % (CWAgent) - AutoSearch:** `SEARCH('{CWAgent,InstanceId,device,fstype,path} MetricName="disk_used_percent" AND InstanceId="${instance_id}"', 'Average', 60)` - ID e1, label Disk / %

Fixed syntax note: Previously had `metrics: [{expression}]` which caused `InvalidParameterInput: Should be array, not object`. Must be `metrics: [[{expression, id, label}]]`

### Row 4: Correlation View (y=24)
- Single graph: api_latency Average, request_count Sum, error_count Sum red, CPUUtilization Average

## Deploy

```bash
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
sed "s/\${instance_id}/$INSTANCE_ID/g" dashboard.json > /tmp/dashboard-final.json
python3 -m json.tool /tmp/dashboard-final.json > /dev/null && echo "valid"
aws cloudwatch put-dashboard --dashboard-name proj2-dashboard --dashboard-body file:///tmp/dashboard-final.json --region us-east-1
```

## Validation
- All periods 60 (not 10) - earlier error `Should NOT have additional properties: {"period": 10}`
- SEARCH uses Average 60
- Memory and Disk use CWAgent namespace (requires CloudWatch Agent installed)
- If CWAgent metrics missing, check agent is running: `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status`

## Customization
- Add dimension Endpoint: change `send_metric` in app.py to include `Dimensions=[{'Name':'Path','Value':path}]`, then dashboard SEARCH needs to filter
- Change region: all widgets have `"region": "us-east-1"`
