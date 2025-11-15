# Envoy: External Authorization

1. External Authorization (`ext-authz`)を組み込むと、Envoyはリクエストをアップストリームのアプリケーションにプロキシする前に、外部の認可サービス（ExtAuthz Service）に送信してアクセス制御を委任できるようになります。
2. ここでは、前の回答で示したサイドカー構成に、gRPCサービスを使用する`ext-authz`フィルターを追加したサンプルYAMLを示します。
3. Envoyの設定に加え、**外部認証サービス（ExtAuthz Service）** が必要になるため、そのサービスのためのKubernetesリソースも合わせて構成する必要があります。

## ⚙️ 変更点1: Envoyの設定 ConfigMap (`envoy-config.yaml`)

既存の`envoy.yaml`に、以下の2つの大きな変更を加えます。

1. **ExtAuthz ServiceのCluster定義** を追加します。
2. `http_connection_manager`の**フィルターチェーン** に`envoy.filters.http.ext_authz`フィルターを**ルーターの前に** 追加します。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-config
data:
  envoy.yaml: |
    static_resources:
      listeners:
      - name: listener_0
        address:
          socket_address:
            protocol: TCP
            address: 0.0.0.0
            port_value: 10000
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              route_config:
                name: local_route
                virtual_hosts:
                - name: local_service
                  domains: ["*"]
                  routes:
                  - match:
                      prefix: "/"
                    route:
                      cluster: local_app_cluster
              # --- 変更箇所: HTTPフィルターチェーン ---
              http_filters:
              # 1. ExtAuthzフィルターを最初に追加
              - name: envoy.filters.http.ext_authz
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
                  grpc_service:
                    envoy_grpc:
                      # ExtAuthzサービスを参照するクラスター名
                      cluster_name: ext_authz_cluster
                    timeout: 0.5s
                  # 認証サービスが応答しない（失敗）場合に、リクエストを許可しない設定
                  failure_mode_allow: false
              # 2. ルーターフィルターをExtAuthzの後に配置
              - name: envoy.filters.http.router
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

      clusters:
      # --- 変更箇所: ExtAuthz ServiceのCluster定義 ---
      - name: ext_authz_cluster
        connect_timeout: 0.5s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: ext_authz_cluster
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: ext-authz-service # 後述のK8s Service名
                    port_value: 9000 # ExtAuthzサービスがgRPCでリッスンするポート

      # --- 既存: アプリケーションコンテナのCluster定義 ---
      - name: local_app_cluster
        connect_timeout: 0.5s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: local_app_cluster
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: 127.0.0.1
                    port_value: 8080
```

## 🚀 変更点2: ExtAuthzサービス用のリソース

Envoyがアクセスできる場所にExtAuthzサービスをデプロイする必要があります。ここでは、架空の認証サービスをデプロイするための最小限の`Deployment`と`Service`のサンプルを示します。

### 1. ExtAuthz ServiceのDeployment (`ext-authz-deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ext-authz-server
  labels:
    app: ext-authz
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ext-authz
  template:
    metadata:
      labels:
        app: ext-authz
    spec:
      containers:
      - name: authz-server
        # 認可ロジックを持つ実際の認証サービスのイメージを指定
        image: **[ExtAuthzサービスのDockerイメージ]**
        ports:
        - containerPort: 9000 # gRPCでEnvoyからのリクエストを受け付けるポート
```

### 2. ExtAuthz ServiceのService (`ext-authz-service.yaml`)

EnvoyのConfigMapで定義した`ext-authz-service`という名前で、認証サーバーのPodを公開します。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ext-authz-service # EnvoyのConfigMapで参照している名前と一致させる
spec:
  selector:
    app: ext-authz
  ports:
    - protocol: TCP
      port: 9000 # Serviceのポート
      targetPort: 9000 # Deploymentのコンテナポート
  type: ClusterIP
```

### 📝 デプロイ手順（ExtAuthz追加版）

1. **ExtAuthzサービスをデプロイ:**

    ```bash
    kubectl apply -f ext-authz-deployment.yaml
    kubectl apply -f ext-authz-service.yaml
    ```

2. **Envoy ConfigMapを適用（更新）:**

    ```bash
    kubectl apply -f envoy-config.yaml
    ```

3. **メインアプリケーションのDeploymentを適用:**

    （Envoyの設定はConfigMapを参照しているため、DeploymentのYAML自体は変更不要ですが、再デプロイまたはローリングアップデートで新しいConfigMapを読み込ませる必要があります。）

    ```bash
    kubectl apply -f my-app-deployment.yaml
    ```

これにより、クライアントからのリクエストは、Envoyに到達した後、まず`ext-authz-service:9000`に認証の問い合わせを行い、その応答に基づいてアプリケーションへのルーティング（許可）またはリクエストの拒否が行われます。
