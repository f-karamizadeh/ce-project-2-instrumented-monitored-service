# make traffic
- for i in {1..250}; do    curl -s -X POST http://44.201.34.190:5000/orders -H "Content-Type: application/json" -d "{\"amount\": $i, \"item\": \"book\"}" > /dev/null;   echo "sent $i";   sleep 0.5; done


- for i in {1..250}; do    curl -s -X POST http://44.201.34.190:5000/orders -H "Content-Type: application/json" -d "{\"amount\": $i, \"item\": \"pen\"}" > /dev/null;   echo "sent $i";   sleep 0.5; done


- for i in {1..250}; do curl http://44.201.34.190:5000/orders; sleep 1; done
- for i in {1..250}; do curl http://44.201.34.190:5000/fail; sleep 1; done
## or on ec2
for i in {1..250}; do    curl -s -X POST localhost:5000/orders -H "Content-Type: application/json" -d "{\"amount\": $i, \"item\": \"book\"}" > /dev/null;   echo "sent $i";   sleep 0.5; done

- and ...


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

# High Error Rate
SOURCE "arn:aws:logs:us-east-1:204146947593:log-group:proj2-logs" START=-604800s END=0s |
fields @timestamp, correlation_id, path, status_code, level
| filter status_code >= 500
| sort @timestamp desc
| limit 20

# High Latency
SOURCE "arn:aws:logs:us-east-1:204146947593:log-group:proj2-logs" START=-604800s END=0s |
fields latency_ms, path, correlation_id
| filter event="request_completed"
| stats avg(latency_ms), max(latency_ms), pct(latency_ms, 95) by bin(1m), path
| sort avg_latency desc
```
---
# triger SNS alarm and Email
- for i in {1..20}; do curl http://44.201.34.190:5000/fail; done

---
#  Incident Response Simulation
- request_count / traffic & latency
  - for i in {1..150}; do 
  curl -s -X POST http://44.201.34.190:5000/orders -H "Content-Type: application/json" -d "{\"amount\": $i, \"item\": \"test\"}" > /dev/null
  echo "sent $i"
  sleep 0.5
done
  - for i in {1..100}; do curl -s http://44.201.34.190:5000/orders  & done
- 