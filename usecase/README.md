# Envoy usecase: simple

1. アプリケーションの**サイドカー** としてデプロイする
2. **Ingress Controller** としてデプロイする
3. **API Gateway** としてデプロイする

## Envoy sidecar

### Deployment as Envoy sidecar

この例では、Envoyはサイドカーとして、同一Pod内の**ポート8080** で動作する**メインのアプリケーションコンテナ** へのトラフィックを、**ポート10000** で受け付けてプロキシします。

これは、アプリケーションコンテナとEnvoyコンテナを両方含むKubernetesの`Deployment`リソースのYAMLです。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-with-envoy
  labels:
    app: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      volumes:
        # Envoyの設定ファイルを格納するConfigMapをマウント
        - name: envoy-config-volume
          configMap:
            name: envoy-config
      containers:
        # 1. メインのアプリケーションコンテナ
        - name: my-app-container
          image: **[あなたのアプリケーションのDockerイメージ]**
          ports:
            - containerPort: 8080
          # アプリケーションがヘルスチェックエンドポイントを持つ場合
          # readinessProbe:
          #   httpGet:
          #     path: /health
          #     port: 8080

        # 2. Envoyサイドカーコンテナ
        - name: envoy-sidecar
          image: envoyproxy/envoy:v1.27.0 # 最新の安定版を使用することを推奨
          ports:
            - containerPort: 10000 # Envoyが外部トラフィックを受け付けるポート
          volumeMounts:
            - name: envoy-config-volume
              mountPath: /etc/envoy # ConfigMapの内容をマウントするパス
          command: ["/usr/local/bin/envoy"]
          args:
            - "--config-path"
            - "/etc/envoy/envoy.yaml" # マウントしたConfigMap内の設定ファイル名
            - "--service-cluster"
            - "my-app-cluster"
            - "--service-node"
            - "$(POD_NAME)"
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
```

### Envoy Configure: ConfigMap

Envoyの動作を設定するための`ConfigMap`です。Envoyはリスナー（トラフィックを受け付ける）とクラスタ（トラフィックをルーティングする宛先）を設定する必要があります。

この例では、Envoyはポート`10000`でトラフィックを受け付け、同一Pod内の`127.0.0.1:8080`で動作しているアプリケーションコンテナに転送します。

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
            port_value: 10000 # EnvoyがPod外からトラフィックを受け付けるポート
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": [type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager](https://type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager)
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
              http_filters:
              - name: envoy.filters.http.router
                typed_config:
                  "@type": [type.googleapis.com/envoy.extensions.filters.http.router.v3.Router](https://type.googleapis.com/envoy.extensions.filters.http.router.v3.Router)

      clusters:
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
                    address: 127.0.0.1 # 同一Pod内のアプリケーションコンテナのIP
                    port_value: 8080 # アプリケーションコンテナのポート

```

### Deploy

1. **ConfigMapの適用:**

    ```bash
    kubectl apply -f envoy-config.yaml
    ```

2. **Deploymentの適用:**

    ```bash
    kubectl apply -f deployment.yaml
    ```

3. **Serviceの作成（オプション）:**
    外部からアクセスできるようにするには、`Deployment`のラベルに一致する`Service`を作成し、Envoyが公開しているポート（例では`10000`）を公開します。

    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: my-app-service
    spec:
      selector:
        app: my-app # Deploymentのラベルと一致
      ports:
        - protocol: TCP
          port: 80 # Serviceのポート
          targetPort: 10000 # Envoyコンテナのポート
      type: LoadBalancer # または ClusterIP, NodePort
    ```

    ```bash
    kubectl apply -f service.yaml
    ```

この設定により、外部からのトラフィックはServiceを経由してEnvoyのサイドカー（ポート10000）に到達し、そこからアプリケーションコンテナ（ポート8080）へとルーティングされます。

Envoyを**Ingress Controller**または**API Gateway**としてKubernetesにデプロイするサンプルと、それぞれのユースケースについて解説します。

## Ingress Controller Envoy

EnvoyをIngress Controllerとしてデプロイする場合、Kubernetesクラスターの**境界** に配置され、クラスター外部からのトラフィックを内部のServiceにルーティングする役割を果たします。

### Usecase

* **L7（HTTP/S）トラフィックルーティング:** ホスト名やパスベースのルーティング（例: `example.com/api`をService Aへ、`example.com/web`をService Bへ）を実現します。
* **TLS終端:** クライアントからのHTTPS接続を受け付け、SSL/TLSを復号し、内部のアプリケーションには平文（HTTP）でトラフィックを転送します。
* **負荷分散とヘルスチェック:** 外部トラフィックを効率的にバックエンドに分散させ、Serviceのヘルスチェックに基づいてトラフィックを遮断します。

### サンプル構成の概念

純粋なEnvoy単体でIngress Controllerを構築する場合、Kubernetesの`Ingress`リソースを監視し、その定義を動的にEnvoyの設定（xDS）に変換して配信する**Control Plane** が必要になります。このControl Planeには、**Envoy Gateway** や**Contour** （Envoyベースの著名なIngress Controller）などが使われます。

ここでは、Contourを使ったデプロイの基本構成（ContourがEnvoyをデプロイ・設定する）を例として示します。

#### Contour + Envoy Ingress Controller (概念図)

| リソース | 役割 |
| :--- | :--- |
| **Contour** (Deployment) | Control Plane。`Ingress`や`HTTPProxy`リソースを監視し、Envoyに動的な設定（xDS）を配信する。 |
| **Envoy** (DaemonSet/Deployment) | Data Plane。Contourから設定を受け取り、実際に外部トラフィックをルーティングする。 |
| **Service (Type: LoadBalancer)** | 外部からのトラフィックをEnvoy Podに公開する。 |

**EnvoyのYAMLサンプル（Contour使用時）:**

Envoy単体のYAMLを手動で書くのではなく、Contourが自動でEnvoyのDeploymentとServiceを管理するため、ユーザーが直接EnvoyのYAMLを書く必要はありません。

1. Contour/Envoyのデプロイ (Contourを例として使用)

    ```bash
    # Contourの公式ドキュメントに従ってデプロイします
    kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
    ```

2. Ingress定義 (ContourがEnvoyに設定を配信)

    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
    name: example-ingress
    spec:
    rules:
    - host: myapp.example.com
        http:
        paths:
        - path: /
            pathType: Prefix
            backend:
            service:
                name: my-app-service
                port:
                number: 8080
    ```

EnvoyはContourからこの設定を受け取り、`myapp.example.com`へのトラフィックを`my-app-service`にルーティングします。

## API Gateway Envoy

EnvoyをAPI Gatewayとしてデプロイする場合、Ingress Controllerよりもさらに**高度なリクエスト処理機能** を提供する役割を果たします。

### Usecase

* **集中的な認証・認可:** すべてのAPIリクエストに対して、`ext-authz`フィルターやJWT認証フィルターを使用して、外部認証サービスと連携した厳密なアクセス制御を適用します。
* **レート制限:** `rate_limit`フィルターを使用して、クライアントやAPIキーごとにアクセス頻度を制限し、バックエンドの過負荷を防ぎます。
* **複雑なトラフィック操作:**
  * **ヘッダ操作:** 特定のAPIキーやユーザー情報に基づいてヘッダを追加・削除・変更します。
  * **ルーティングの細分化:** URLだけでなく、リクエストヘッダやクエリパラメータに基づいてルーティングを決定します（カナリアリリースやA/Bテスト）。
* **メッシュとの連携:** API Gatewayは外部からのトラフィックを受け持つ「南北」トラフィックを担当し、内部のマイクロサービス間の「東西」トラフィックを**サービスメッシュ（例: Istio, Linkerd）**で管理することで、強力なゼロトラスト環境を構築できます。

### サンプル構成の概念

API GatewayとしてEnvoyを使う場合、通常は**サービスメッシュ**の一部としてデプロイされます。Istioの**Ingress Gateway**などが代表的です。

#### Istio Ingress Gateway (Envoy) Deploy

| リソース | 役割 |
| :--- | :--- |
| **Istiod** (Control Plane) | Istioの設定（`Gateway`や`VirtualService`）を監視し、Envoy Gatewayに動的な設定（xDS）を配信する。 |
| **Istio Ingress Gateway** (Deployment/Service) | Envoyベースのデータプレーン。外部トラフィックをクラスター内のサービスメッシュに引き込む。 |
| **VirtualService/Gateway** | ユーザーが認証、レート制限、ルーティングなどのポリシーを定義するリソース。 |

**Istio Gateway + VirtualService サンプル**

これは、Istioを通じてEnvoyにレート制限とルーティングを設定する例です。

1. Gateway定義 (トラフィックの入り口)

    ```yaml
    apiVersion: networking.istio.io/v1beta1
    kind: Gateway
    metadata:
    name: my-gateway
    spec:
    selector:
        istio: ingressgateway # Envoy Podのラベル
    servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
        hosts:
        - "*"
    ```

2. VirtualService定義 (ルーティングとポリシー)

    ```yaml
    apiVersion: networking.istio.io/v1beta1
    kind: VirtualService
    metadata:
    name: my-api-vs
    spec:
    hosts:
    - "*"
    gateways:
    - my-gateway # 上で定義したGatewayと関連付け

    # --- レート制限の定義（Envoyが実行） ---
    http:
    - match:
        - uri:
            prefix: /api/v1/products
        # レート制限の設定（IstioのRateLimitServiceと連携）
        rateLimit:
        - actions:
        - remoteAddress: {} # クライアントIPに基づく制限
        # ... その他のレート制限設定 ...

        # --- ルーティングの定義 ---
        route:
        - destination:
            host: products-service # バックエンドのサービス
            port:
            number: 8080
    ```

Envoy（Istio Gateway）はこれらのリソース定義をControl Planeから受け取り、API Gatewayとして機能します。

| 役割 | Ingress Controller | API Gateway |
| :--- | :--- | :--- |
| **主な目的** | クラスター境界での**L7ルーティング**とTLS終端。 | APIの**高度なポリシー適用**（認証、認可、レート制限）。 |
| **機能の深さ** | 基本的なルーティング、負荷分散。 | 高度なフィルタリング、リクエスト/レスポンスの変換、セキュリティ機能。 |
| **デプロイ形態** | クラスターの入口に専用でデプロイされることが多い。 | サービスメッシュのコンポーネントとしてデプロイされることが多い。 |
| **例** | Contour, NGINX Ingress, HAProxy Ingress | Istio Ingress Gateway, Gloo Gateway |
