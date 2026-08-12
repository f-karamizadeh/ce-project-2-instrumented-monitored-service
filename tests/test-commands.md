# make traffic
- curl -X POST http://44.201.34.190:5000/orders -H "Content-Type: application/json" -d '{"amount": 120, "item": "book"}'

- curl -X POST http://44.201.34.190:5000/orders -H "Content-Type: application/json" -d '{"amount": 45, "item": "pen"}'

- for i in {1..20}; do curl http://44.201.34.190:5000/orders; sleep 1; done
## or
- curl -X POST localhost:5000/orders -H "Content-Type: application/json" -d '{"amount": 120, "item": "book"}'

- curl -X POST localhost:5000/orders -H "Content-Type: application/json" -d '{"amount": 45, "item": "pen"}' 

# on EC2
for i in {1..20}; do curl localhost:5000/orders; sleep 1; done

