#!/bin/bash

# Envoy Proxy サンプルアプリケーション セットアップスクリプト
# このスクリプトは、Kindクラスター上にEnvoyサンプルアプリケーションをデプロイします

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ディレクトリの確認
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}Envoy Proxy サンプルアプリケーション セットアップを開始します...${NC}"

# Kindクラスターの確認
if ! kind get clusters | grep -q "envoy-demo"; then
  echo -e "${YELLOW}Kindクラスター 'envoy-demo' が見つかりません。作成します...${NC}"
  kind create cluster --name envoy-demo
else
  echo -e "${GREEN}Kindクラスター 'envoy-demo' が見つかりました。${NC}"
fi

# kubectlの確認
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}kubectl が見つかりません。インストールしてください。${NC}"
  exit 1
fi

# 必要なディレクトリの作成
mkdir -p manifests configs services/frontend services/backend-a services/backend-b

# 名前空間の作成
echo -e "${GREEN}名前空間を作成しています...${NC}"
cat <<EOF > manifests/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: envoy-demo
EOF

kubectl apply -f manifests/namespace.yaml

# データベースのデプロイ
echo -e "${GREEN}データベースをデプロイしています...${NC}"
cat <<EOF > manifests/database.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: envoy-demo
spec:
  selector:
    matchLabels:
      app: database
  replicas: 1
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: database
        image: mongo:4.4
        ports:
        - containerPort: 27017
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: envoy-demo
spec:
  selector:
    app: database
  ports:
  - port: 27017
    targetPort: 27017
EOF

kubectl apply -f manifests/database.yaml

# バックエンドサービスAの設定ファイル
echo -e "${GREEN}バックエンドサービスAの設定ファイルを作成しています...${NC}"
cat <<EOF > configs/backend-a-envoy.yaml
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 9901
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: local_service
  clusters:
  - name: local_service
    connect_timeout: 0.25s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: local_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 8080
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# バックエンドサービスAのデプロイ
echo -e "${GREEN}バックエンドサービスAをデプロイしています...${NC}"
cat <<EOF > services/backend-a/app.js
const express = require('express');
const app = express();
const port = 8080;

app.use(express.json());

// サンプルデータ
const items = [
  { id: 1, name: 'Item 1', category: 'Category A' },
  { id: 2, name: 'Item 2', category: 'Category B' },
  { id: 3, name: 'Item 3', category: 'Category A' }
];

// ルートエンドポイント
app.get('/', (req, res) => {
  res.send('Backend Service A is running!');
});

// アイテム一覧を取得
app.get('/api/items', (req, res) => {
  res.json(items);
});

// 特定のアイテムを取得
app.get('/api/items/:id', (req, res) => {
  const item = items.find(i => i.id === parseInt(req.params.id));
  if (!item) return res.status(404).send('Item not found');
  res.json(item);
});

// ヘルスチェック
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(\`Backend Service A listening at http://localhost:\${port}\`);
});
EOF

cat <<EOF > services/backend-a/Dockerfile
FROM node:14-alpine

WORKDIR /app

COPY package.json .
RUN npm install

COPY app.js .

EXPOSE 8080

CMD ["node", "app.js"]
EOF

cat <<EOF > services/backend-a/package.json
{
  "name": "backend-a",
  "version": "1.0.0",
  "description": "Backend Service A for Envoy Demo",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.17.1"
  }
}
EOF

cat <<EOF > manifests/backend-a.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-a
  namespace: envoy-demo
spec:
  selector:
    matchLabels:
      app: backend-a
  replicas: 2
  template:
    metadata:
      labels:
        app: backend-a
    spec:
      containers:
      - name: app
        image: node:14-alpine
        command: ["node", "/app/app.js"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app-code
          mountPath: /app
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      - name: envoy
        image: envoyproxy/envoy:v1.28.0
        ports:
        - containerPort: 9901
        - containerPort: 10000
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: app-code
        configMap:
          name: backend-a-code
      - name: envoy-config
        configMap:
          name: backend-a-envoy-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-a
  namespace: envoy-demo
spec:
  selector:
    app: backend-a
  ports:
  - name: http
    port: 80
    targetPort: 10000
  - name: admin
    port: 9901
    targetPort: 9901
EOF

# バックエンドサービスAのConfigMapを作成
kubectl create configmap backend-a-code --from-file=app.js=services/backend-a/app.js --from-file=package.json=services/backend-a/package.json -n envoy-demo
kubectl create configmap backend-a-envoy-config --from-file=envoy.yaml=configs/backend-a-envoy.yaml -n envoy-demo

# バックエンドサービスBの設定ファイル
echo -e "${GREEN}バックエンドサービスBの設定ファイルを作成しています...${NC}"
cat <<EOF > configs/backend-b-envoy.yaml
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 9901
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: local_service
  clusters:
  - name: local_service
    connect_timeout: 0.25s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: local_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 8080
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# バックエンドサービスBのデプロイ
echo -e "${GREEN}バックエンドサービスBをデプロイしています...${NC}"
cat <<EOF > services/backend-b/app.js
const express = require('express');
const app = express();
const port = 8080;

app.use(express.json());

// サンプルデータ
const users = [
  { id: 1, name: 'User 1', email: 'user1@example.com' },
  { id: 2, name: 'User 2', email: 'user2@example.com' },
  { id: 3, name: 'User 3', email: 'user3@example.com' }
];

// ルートエンドポイント
app.get('/', (req, res) => {
  res.send('Backend Service B is running!');
});

// ユーザー一覧を取得
app.get('/api/users', (req, res) => {
  res.json(users);
});

// 特定のユーザーを取得
app.get('/api/users/:id', (req, res) => {
  const user = users.find(u => u.id === parseInt(req.params.id));
  if (!user) return res.status(404).send('User not found');
  res.json(user);
});

// ヘルスチェック
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(\`Backend Service B listening at http://localhost:\${port}\`);
});
EOF

cat <<EOF > services/backend-b/Dockerfile
FROM node:14-alpine

WORKDIR /app

COPY package.json .
RUN npm install

COPY app.js .

EXPOSE 8080

CMD ["node", "app.js"]
EOF

cat <<EOF > services/backend-b/package.json
{
  "name": "backend-b",
  "version": "1.0.0",
  "description": "Backend Service B for Envoy Demo",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.17.1"
  }
}
EOF

cat <<EOF > manifests/backend-b.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-b
  namespace: envoy-demo
spec:
  selector:
    matchLabels:
      app: backend-b
  replicas: 2
  template:
    metadata:
      labels:
        app: backend-b
    spec:
      containers:
      - name: app
        image: node:14-alpine
        command: ["node", "/app/app.js"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app-code
          mountPath: /app
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      - name: envoy
        image: envoyproxy/envoy:v1.28.0
        ports:
        - containerPort: 9901
        - containerPort: 10000
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: app-code
        configMap:
          name: backend-b-code
      - name: envoy-config
        configMap:
          name: backend-b-envoy-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-b
  namespace: envoy-demo
spec:
  selector:
    app: backend-b
  ports:
  - name: http
    port: 80
    targetPort: 10000
  - name: admin
    port: 9901
    targetPort: 9901
EOF

# バックエンドサービスBのConfigMapを作成
kubectl create configmap backend-b-code --from-file=app.js=services/backend-b/app.js --from-file=package.json=services/backend-b/package.json -n envoy-demo
kubectl create configmap backend-b-envoy-config --from-file=envoy.yaml=configs/backend-b-envoy.yaml -n envoy-demo

# フロントエンドサービスの設定ファイル
echo -e "${GREEN}フロントエンドサービスの設定ファイルを作成しています...${NC}"
cat <<EOF > configs/frontend-envoy.yaml
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 10000
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/api/service-a/"
                route:
                  prefix_rewrite: "/api/"
                  cluster: backend_a
                  timeout: 5s
                  retry_policy:
                    retry_on: connect-failure,refused-stream,unavailable,cancelled,resource-exhausted,5xx
                    num_retries: 3
                    per_try_timeout: 1s
              - match:
                  prefix: "/api/service-b/"
                route:
                  prefix_rewrite: "/api/"
                  cluster: backend_b
                  timeout: 5s
                  retry_policy:
                    retry_on: connect-failure,refused-stream,unavailable,cancelled,resource-exhausted,5xx
                    num_retries: 3
                    per_try_timeout: 1s
              - match:
                  prefix: "/"
                route:
                  cluster: local_service
  clusters:
  - name: local_service
    connect_timeout: 0.25s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: local_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 8080
  - name: backend_a
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    circuit_breakers:
      thresholds:
      - priority: DEFAULT
        max_connections: 100
        max_pending_requests: 100
        max_requests: 100
        max_retries: 3
    load_assignment:
      cluster_name: backend_a
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: backend-a
                port_value: 80
  - name: backend_b
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    circuit_breakers:
      thresholds:
      - priority: DEFAULT
        max_connections: 100
        max_pending_requests: 100
        max_requests: 100
        max_retries: 3
    load_assignment:
      cluster_name: backend_b
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: backend-b
                port_value: 80
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# フロントエンドサービスのデプロイ
echo -e "${GREEN}フロントエンドサービスをデプロイしています...${NC}"
cat <<EOF > services/frontend/index.html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Envoy Demo</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      padding: 20px;
      line-height: 1.6;
    }
    .container {
      max-width: 800px;
      margin: 0 auto;
    }
    h1 {
      color: #333;
      border-bottom: 2px solid #eee;
      padding-bottom: 10px;
    }
    .card {
      background: #f9f9f9;
      border: 1px solid #ddd;
      border-radius: 4px;
      padding: 15px;
      margin-bottom: 20px;
    }
    .button {
      display: inline-block;
      background: #4CAF50;
      color: white;
      padding: 8px 16px;
      margin-right: 10px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
    }
    .button:hover {
      background: #45a049;
    }
    pre {
      background: #f4f4f4;
      border: 1px solid #ddd;
      border-radius: 3px;
      padding: 10px;
      overflow: auto;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>Envoy Proxy デモアプリケーション</h1>
    
    <div class="card">
      <h2>サービスA - アイテム一覧</h2>
      <button class="button" onclick="fetchItems()">アイテムを取得</button>
      <div id="items-result"></div>
    </div>
    
    <div class="card">
      <h2>サービスB - ユーザー一覧</h2>
      <button class="button" onclick="fetchUsers()">ユーザーを取得</button>
      <div id="users-result"></div>
    </div>
  </div>

  <script>
    async function fetchItems() {
      const resultDiv = document.getElementById('items-result');
      resultDiv.innerHTML = 'Loading...';
      
      try {
        const response = await fetch('/api/service-a/items');
        const data = await response.json();
        
        resultDiv.innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
      } catch (error) {
        resultDiv.innerHTML = '<p style="color: red;">Error: ' + error.message + '</p>';
      }
    }
    
    async function fetchUsers() {
      const resultDiv = document.getElementById('users-result');
      resultDiv.innerHTML = 'Loading...';
      
      try {
        const response = await fetch('/api/service-b/users');
        const data = await response.json();
        
        resultDiv.innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
      } catch (error) {
        resultDiv.innerHTML = '<p style="color: red;">Error: ' + error.message + '</p>';
      }
    }
  </script>
</body>
</html>
EOF

cat <<EOF > services/frontend/app.js
const express = require('express');
const path = require('path');
const app = express();
const port = 8080;

// 静的ファイルの提供
app.use(express.static(path.join(__dirname, 'public')));

// ルートエンドポイント
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ヘルスチェック
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(\`Frontend service listening at http://localhost:\${port}\`);
});
EOF

cat <<EOF > services/frontend/Dockerfile
FROM node:14-alpine

WORKDIR /app

COPY package.json .
RUN npm install

COPY app.js .
COPY public/ ./public/

EXPOSE 8080

CMD ["node", "app.js"]
EOF

cat <<EOF > services/frontend/package.json
{
  "name": "frontend",
  "version": "1.0.0",
  "description": "Frontend Service for Envoy Demo",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.17.1"
  }
}
EOF

cat <<EOF > manifests/frontend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: envoy-demo
spec:
  selector:
    matchLabels:
      app: frontend
  replicas: 1
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: app
        image: node:14-alpine
        command: ["node", "/app/app.js"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app-code
          mountPath: /app
        - name: app-public
          mountPath: /app/public
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      - name: envoy
        image: envoyproxy/envoy:v1.28.0
        ports:
        - containerPort: 9901
        - containerPort: 10000
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: app-code
        configMap:
          name: frontend-code
      - name: app-public
        configMap:
          name: frontend-public
      - name: envoy-config
        configMap:
          name: frontend-envoy-config
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: envoy-demo
spec:
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 10000
  - name: admin
    port: 9901
    targetPort: 9901
EOF

# フロントエンドのConfigMapを作成
mkdir -p services/frontend/public
cp services/frontend/index.html services/frontend/public/
kubectl create configmap frontend-code --from-file=app.js=services/frontend/app.js --from-file=package.json=services/frontend/package.json -n envoy-demo
kubectl create configmap frontend-public --from-file=index.html=services/frontend/public/index.html -n envoy-demo
kubectl create configmap frontend-envoy-config --from-file=envoy.yaml=configs/frontend-envoy.yaml -n envoy-demo

# Ingressゲートウェイの設定ファイル
echo -e "${GREEN}Ingressゲートウェイの設定ファイルを作成しています...${NC}"
cat <<EOF > configs/ingress-envoy.yaml
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 80
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: frontend
  clusters:
  - name: frontend
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: frontend
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: frontend
                port_value: 80
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# Ingressゲートウェイのデプロイ
echo -e "${GREEN}Ingressゲートウェイをデプロイしています...${NC}"
cat <<EOF > manifests/ingress.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingress-gateway
  namespace: envoy-demo
spec:
  selector:
    matchLabels:
      app: ingress-gateway
  replicas: 1
  template:
    metadata:
      labels:
        app: ingress-gateway
    spec:
      containers:
      - name: envoy
        image: envoyproxy/envoy:v1.28.0
        ports:
        - containerPort: 80
        - containerPort: 9901
        volumeMounts:
        - name: envoy-config
          mountPath: /etc/envoy
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: envoy-config
        configMap:
          name: ingress-envoy-config
---
apiVersion: v1
kind: Service
metadata:
  name: ingress-gateway
  namespace: envoy-demo
spec:
  selector:
    app: ingress-gateway
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: admin
    port: 9901
    targetPort: 9901
  type: NodePort
EOF

# Ingressゲートウェイの設定をConfigMapとして作成
kubectl create configmap ingress-envoy-config --from-file=envoy.yaml=configs/ingress-envoy.yaml -n envoy-demo

# マニフェストの適用
echo -e "${GREEN}Kubernetesマニフェストを適用しています...${NC}"
kubectl apply -f manifests/backend-a.yaml
kubectl apply -f manifests/backend-b.yaml
kubectl apply -f manifests/frontend.yaml
kubectl apply -f manifests/ingress.yaml

# デプロイの状態を確認
echo -e "${GREEN}デプロイの状態を確認しています...${NC}"
kubectl get pods -n envoy-demo

echo -e "${GREEN}セットアップが完了しました！${NC}"
echo -e "${YELLOW}アプリケーションにアクセスするには、以下のコマンドを実行してください：${NC}"
echo -e "kubectl port-forward -n envoy-demo svc/ingress-gateway 8080:80"
echo -e "${YELLOW}その後、ブラウザで http://localhost:8080 にアクセスしてください。${NC}"
