# Send metric
cw_client = boto3.client('cloudwatch', region_name='us-east-1')

def send_metric(name, value, unit='Count'):
    try:
        cw_client.put_metric_data(
            Namespace='Proj2/MyApp',
            MetricData=[{'MetricName': name, 'Value': value, 'Unit': unit, 'Timestamp': datetime.utcnow()}]
        )
    except Exception as e:
        print(f"Metric error: {e}")

app = Flask(__name__)
orders = []


# JSON format

@app.after_request
def after(response):
    latency = int((time.time() - g.start_time) * 1000)
    
  
    log.info("request_completed",
        correlation_id=g.correlation_id,
        method=request.method,
        path=request.path,
        status_code=response.status_code,
        latency_ms=latency,
        level="ERROR" if response.status_code >= 500 else "WARN" if response.status_code >= 400 else "INFO"
    )