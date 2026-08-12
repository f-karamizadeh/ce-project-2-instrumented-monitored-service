from flask import Flask, request, jsonify, g
import structlog
import uuid
import time
import random
import boto3
from datetime import datetime

# --- تنظیمات لاگ JSON ---
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ]
)
log = structlog.get_logger()

# --- تنظیمات متریک ---
# این کلاینت متریک ها رو میفرسته به CloudWatch
cw_client = boto3.client('cloudwatch', region_name='us-east-1')

def send_metric(name, value, unit='Count'):
    try:
        cw_client.put_metric_data(
            Namespace='Proj2/MyApp',
            MetricData=[{'MetricName': name, 'Value': value, 'Unit': unit, 'Timestamp': datetime.utcnow()}]
        )
    except Exception as e:
        # اگه اینترنت نبود برنامه کرش نکنه
        print(f"Metric error: {e}")

app = Flask(__name__)
orders = [] # یه دیتابیس خیلی ساده تو حافظه

@app.before_request
def before():
    g.correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    g.start_time = time.time()

@app.after_request
def after(response):
    latency = int((time.time() - g.start_time) * 1000)
    
    # لاگ ساختارمند - این مهمترین بخش پروژه است
    log.info("request_completed",
        correlation_id=g.correlation_id,
        method=request.method,
        path=request.path,
        status_code=response.status_code,
        latency_ms=latency,
        level="ERROR" if response.status_code >= 500 else "WARN" if response.status_code >= 400 else "INFO"
    )
    
    # متریک ها
    send_metric('request_count', 1)
    send_metric('api_latency', latency, 'Milliseconds')
    if response.status_code >= 400:
        send_metric('error_count', 1)

    return response

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "version": "1.0"}), 200

@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    if not data or 'amount' not in data:
        return jsonify({"error": "amount required"}), 400
    
    order = {
        "id": str(uuid.uuid4()),
        "amount": data['amount'],
        "item": data.get('item', 'unknown'),
        "correlation_id": g.correlation_id,
        "created_at": datetime.utcnow().isoformat()
    }
    orders.append(order)

    # لاگ بیزینسی
    log.info("order_created", order_id=order['id'], amount=order['amount'], correlation_id=g.correlation_id)
    
    # متریک های بیزینسی
    send_metric('orders_per_minute', 1)
    send_metric('order_value', order['amount'])

    return jsonify(order), 201

@app.route('/orders', methods=['GET'])
def list_orders():
    return jsonify(orders), 200

@app.route('/fail', methods=['GET'])
def fail():
    # این برای تست آلارم و سناریو خرابی بعدا لازم میشه
    if random.random() < 0.5:
        return jsonify({"error": "injected failure"}), 500
    return jsonify({"msg": "ok"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)