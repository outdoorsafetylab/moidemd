apiVersion: apps/v1
kind: Deployment
metadata:
  name: moidemd
  labels:
    app: moidemd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: moidemd
  template:
    metadata:
      labels:
        app: moidemd
    spec:
      containers:
      - name: moidemd
        image: gcr.io/GOOGLE_CLOUD_PROJECT/moidemd:COMMIT_SHA
        ports:
        - containerPort: 8080
---
kind: Service
apiVersion: v1
metadata:
  name: moidemd
spec:
  selector:
    app: moidemd
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer