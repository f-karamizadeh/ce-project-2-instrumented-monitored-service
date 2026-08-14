# CloudWatch Dashboard Showing "No Data" for CWAgent Metrics

## Context
- **EC2:** `proj2-app-server` (`i-01b042962afdf4a30`)
- **Agent:** Amazon CloudWatch Agent sending `mem_used_percent` and `disk_used_percent` to `CWAgent` namespace
- **IaC:** Terraform module `modules/monitoring` with `aws_cloudwatch_dashboard`
- **Symptom:** Dashboard `proj2-dashboard` widgets for Memory and Disk showed `No data available`, while `aws cloudwatch list-metrics` returned results.

## Root Cause Analysis - 3 Overlapping Issues

### 1. Stale Metrics from Terminated Instances
`aws cloudwatch list-metrics --namespace CWAgent` showed metrics but they belonged to old terminated instances.

```bash
aws cloudwatch list-metrics --namespace CWAgent --metric-name mem_used_percent --query "Metrics[].Dimensions"

# Output:
# i-0aecabd3977290b34  <- old
# i-05aa2b7dd63d8cbe1  <- old
# host=ip-10-0-1-221.ec2.internal <- current, but not InstanceId
```
CloudWatch retains metrics for 15 months, which was misleading.

### 2. Missing `append_dimensions` - Dimension Mismatch
The agent config did not contain `InstanceId`.

Console screenshot showed:
`All > CWAgent > device, fstype, host, path (1)`
`nvme0n1p1 | xfs | ip-10-0-1-221.ec2.internal | / | disk_used_percent`

So agent published with `host` dimension only, while Terraform dashboard queried:
`InstanceId = i-01b042962afdf4a30` -> `[]` result.

### 3. Dashboard Validation & High-Res Issues
- **Disk metric has 4 dimensions:** `device`, `fstype`, `host`, `path`. Filtering by only `InstanceId` returns nothing. Must use `SEARCH()` or specify all 4.
- **Period mismatch:** Config had `interval = "10s"` + `"aws:StorageResolution": "true"` (High-Res 10s) but dashboard used `period=60`.
- **Terraform error:**
```
InvalidParameterInput: The dashboard body is invalid
  /widgets/14/properties/metrics/0 - Should be array
```
`SEARCH` was written as `[{"expression":...}]` instead of `[[{"expression":...}]]`.

## Fix - Step by Step

### Step 1: Verify Agent
```bash
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.toml | grep -E "^\[\[inputs"
# Should show [[inputs.mem]] [[inputs.disk]] [[inputs.logfile]]

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
# status: running

sudo tail -n 50 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log | grep -i "error"
# No errors
```

### Step 2: Fix Agent Config
Update `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`:

```json
{
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/ec2-user/app/app.log",
            "log_group_name": "proj2-logs",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

Reload:
```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
```

### Step 3: Fix Dashboard JSON (Manual Console + Terraform)

**Before (empty):**
```json
["CWAgent", "disk_used_percent", "InstanceId", "i-01b042962afdf4a30"]
```

**After (works - use real dimensions from console):**
```json
{
  "metrics": [
    ["CWAgent", "disk_used_percent", "device", "nvme0n1p1", "fstype", "xfs", "host", "ip-10-0-1-221.ec2.internal", "path", "/", {"stat": "Average", "period": 60, "label": "Disk /"}]
  ],
  "period": 60
}
```

For Memory:
```json
["CWAgent", "mem_used_percent", "host", "ip-10-0-1-221.ec2.internal", {"stat": "Average", "period": 60}]
```
Or after `append_dimensions` fix:
```json
["CWAgent", "mem_used_percent", "InstanceId", "i-01b042962afdf4a30", {"stat": "Average", "period": 60}]
```

**SEARCH syntax fix:**
```json
// Wrong:
"metrics": [{"expression": "SEARCH('{CWAgent,InstanceId,device,fstype,path} MetricName=\"disk_used_percent\" AND InstanceId=\"${instance_id}\"', 'Average', 60)"}]

// Correct (array of array):
"metrics": [[{"expression": "SEARCH('{CWAgent,InstanceId,device,fstype,path} MetricName=\"disk_used_percent\" AND InstanceId=\"${instance_id}\"', 'Average', 60)", "id": "e1", "label": "Disk / %"}]]
```

Console manual fix: `CloudWatch > Dashboards > proj2-dashboard > Actions > View/edit source` -> replace widget -> Save.

### Step 4: Clean IaC Separation
Split into 2 files to prevent overwrite:

**`monitoring.tf`:**
- `variable "alert_email"`
- `data "aws_instance" "app"`
- `aws_sns_topic` + `subscription`
- `aws_cloudwatch_metric_alarm` (high_latency, high_error, high_mem, high_disk)
- `aws_cloudwatch_dashboard` using `templatefile("${path.module}/dashboard.json", {instance_id = ...})`

**`dashboard.json`:**
- Pure JSON, no `jsonencode()`, uses `${instance_id}` placeholder

This prevents accidental `fetch-config -c file:/opt/.../config.json` (logs-only) overwriting the `toml` and deleting `mem/disk` inputs.

## Verification
Wait 60-90s then:
```bash
aws cloudwatch list-metrics --namespace CWAgent --metric-name mem_used_percent --region us-east-1 --dimensions Name=InstanceId,Value=i-01b042962afdf4a30

aws cloudwatch list-metrics --namespace CWAgent --metric-name disk_used_percent --region us-east-1 --dimensions Name=InstanceId,Value=i-01b042962afdf4a30 --query "Metrics[].Dimensions"
```

Should return the current instance and dashboard should show data.

## Key Takeaway
Always check **exact Dimensions** in CloudWatch Console > Metrics > CWAgent > Browse. Disk metrics require 4 dimensions (`device`, `fstype`, `host`, `path`). Using only `InstanceId` will return empty if `append_dimensions` is missing.
