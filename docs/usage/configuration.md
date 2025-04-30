# Envoy 設定ガイド

このドキュメントでは、Envoyの設定ファイルの構造と主要な設定オプションについて詳しく説明します。Envoyの設定は主にYAML形式で記述され、静的設定と動的設定の両方をサポートしています。

## 設定ファイルの基本構造

Envoyの設定ファイルは、以下の主要なセクションで構成されています：

```yaml
static_resources:       # 静的リソース（リスナー、クラスターなど）
  listeners: []         # トラフィックを受信するリスナー
  clusters: []          # バックエンドサービス

dynamic_resources:      # 動的リソース（xDS API設定）
  lds_config: {}        # リスナー検出サービス
  cds_config: {}        # クラスター検出サービス

admin:                  # 管理インターフェース
  address: {}           # 管理インターフェースのアドレス

layered_runtime:        # ランタイム設定
  layers: []            # ランタイム設定のレイヤー
```

## 静的リソース

### リスナー (Listeners)

リスナーは、Envoyがトラフィックを受信するネットワークの場所（IPアドレスとポート）を定義します。

```yaml
listeners:
- name: listener_http
  address:
    socket_address:
      address: 0.0.0.0    # すべてのインターフェースでリッスン
      port_value: 8080    # ポート番号
  filter_chains:          # フィルターチェーン
  - filters:
    - name: envoy.filters.network.http_connection_manager
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
        stat_prefix: ingress_http
        codec_type: AUTO
        route_config:
          # ルート設定（後述）
        http_filters:
          # HTTPフィルター（後述）
```

#### フィルターチェーン

フィルターチェーンは、リスナーに接続されたフィルターのシーケンスを定義します。最も一般的なフィルターは`http_connection_manager`です。

```yaml
filter_chains:
- filters:
  - name: envoy.filters.network.http_connection_manager
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
      stat_prefix: ingress_http
      codec_type: AUTO                # HTTP1.1/HTTP2を自動検出
      access_log:                     # アクセスログ設定
      - name: envoy.access_loggers.file
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
          path: /var/log/envoy/access.log
      route_config:                   # ルート設定
        # ...
      http_filters:                   # HTTPフィルター
        # ...
```

#### TLS設定

リスナーでTLS（HTTPS）を有効にするには、`transport_socket`を設定します：

```yaml
filter_chains:
- transport_socket:
    name: envoy.transport_sockets.tls
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
      common_tls_context:
        tls_certificates:
        - certificate_chain:
            filename: "/etc/envoy/certs/cert.pem"
          private_key:
            filename: "/etc/envoy/certs/key.pem"
  filters:
    # ...
```

### ルート設定 (Route Configuration)

ルート設定は、受信したリクエストをどのクラスターに転送するかを定義します。

```yaml
route_config:
  name: local_route
  virtual_hosts:
  - name: backend
    domains: ["*"]                # このバーチャルホストが処理するドメイン
    routes:
    - match:
        prefix: "/api/v1/"        # このパスプレフィックスにマッチするリクエスト
      route:
        cluster: api_cluster_v1   # 転送先のクラスター
    - match:
        prefix: "/api/v2/"
      route:
        cluster: api_cluster_v2
    - match:
        prefix: "/"               # その他のすべてのリクエスト
      route:
        cluster: default_cluster
```

#### 高度なルーティング

より複雑なルーティングルールも設定できます：

```yaml
routes:
- match:
    prefix: "/api/"
    headers:                      # ヘッダーに基づくマッチング
    - name: "content-type"
      string_match:
        exact: "application/json"
  route:
    cluster: api_json_cluster
    timeout: 5s                   # タイムアウト設定
    retry_policy:                 # 再試行ポリシー
      retry_on: connect-failure,refused-stream
      num_retries: 3
      per_try_timeout: 1s
```

### HTTPフィルター

HTTPフィルターは、HTTPリクエストとレスポンスを処理します。フィルターは指定された順序で実行されます。

```yaml
http_filters:
- name: envoy.filters.http.buffer
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
    max_request_bytes: 8192
- name: envoy.filters.http.router
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

一般的なHTTPフィルターには以下があります：

- **router**: リクエストをアップストリームクラスターにルーティング（必須）
- **buffer**: リクエストボディをバッファリング
- **cors**: Cross-Origin Resource Sharing (CORS) サポート
- **jwt_authn**: JWT認証
- **lua**: Luaスクリプトの実行
- **health_check**: ヘルスチェックエンドポイント
- **gzip**: レスポンスの圧縮
- **fault**: 障害注入（テスト用）

### クラスター (Clusters)

クラスターは、Envoyが接続するバックエンドサービスのグループを定義します。

```yaml
clusters:
- name: service_backend
  connect_timeout: 0.25s
  type: STRICT_DNS                # サービスディスカバリタイプ
  lb_policy: ROUND_ROBIN         # ロードバランシングポリシー
  load_assignment:
    cluster_name: service_backend
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: backend.example.com
              port_value: 80
```

#### サービスディスカバリタイプ

Envoyは以下のサービスディスカバリタイプをサポートしています：

- **STATIC**: 静的IPアドレスのリスト
- **STRICT_DNS**: DNSルックアップ（すべてのIPを使用）
- **LOGICAL_DNS**: DNSルックアップ（最初のIPのみ使用）
- **EDS**: Endpoint Discovery Service（動的）
- **ORIGINAL_DST**: 元の宛先アドレスを使用

#### ロードバランシングポリシー

利用可能なロードバランシングポリシーには以下があります：

- **ROUND_ROBIN**: ラウンドロビン（デフォルト）
- **LEAST_REQUEST**: 最小リクエスト数
- **RING_HASH**: 一貫性のあるハッシュ
- **RANDOM**: ランダム
- **MAGLEV**: Maglev（一貫性のあるハッシュの一種）

#### ヘルスチェック

クラスターのヘルスチェックを設定できます：

```yaml
clusters:
- name: service_backend
  # ...
  health_checks:
  - timeout: 1s
    interval: 10s
    unhealthy_threshold: 3
    healthy_threshold: 2
    http_health_check:
      path: "/health"
      expected_statuses:
        start: 200
        end: 299
```

#### サーキットブレーカー

サーキットブレーカーを設定して、障害からシステムを保護できます：

```yaml
clusters:
- name: service_backend
  # ...
  circuit_breakers:
    thresholds:
    - priority: DEFAULT
      max_connections: 1000
      max_pending_requests: 1000
      max_requests: 5000
      max_retries: 3
```

## 動的設定 (xDS API)

Envoyは、xDS APIを通じて動的に設定を更新できます。

```yaml
dynamic_resources:
  lds_config:
    resource_api_version: V3
    api_config_source:
      api_type: GRPC
      transport_api_version: V3
      grpc_services:
      - envoy_grpc:
          cluster_name: xds_cluster
  cds_config:
    resource_api_version: V3
    api_config_source:
      api_type: GRPC
      transport_api_version: V3
      grpc_services:
      - envoy_grpc:
          cluster_name: xds_cluster

clusters:
- name: xds_cluster
  connect_timeout: 0.25s
  type: STRICT_DNS
  lb_policy: ROUND_ROBIN
  http2_protocol_options: {}
  load_assignment:
    cluster_name: xds_cluster
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: xds-server
              port_value: 18000
```

## 管理インターフェース

管理インターフェースは、統計情報、設定、ログレベルなどの管理機能を提供します。

```yaml
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
  access_log:
  - name: envoy.access_loggers.file
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
      path: /var/log/envoy/admin_access.log
```

## ランタイム設定

ランタイム設定は、Envoyの実行時に動的に変更できるパラメータを定義します。

```yaml
layered_runtime:
  layers:
  - name: static_layer
    static_layer:
      envoy.reloadable_features.http2_use_multiple_connections: false
      overload.global_downstream_max_connections: 50000
  - name: disk_layer
    disk_layer: { symlink_root: /srv/runtime/current, subdirectory: envoy }
  - name: admin_layer
    admin_layer: {}
```

## 高度な設定例

### 1. マイクロサービスプロキシ

複数のマイクロサービスへのルーティングを設定する例：

```yaml
static_resources:
  listeners:
  - name: listener_http
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match:
                  prefix: "/users"
                route:
                  cluster: users_service
              - match:
                  prefix: "/products"
                route:
                  cluster: products_service
              - match:
                  prefix: "/orders"
                route:
                  cluster: orders_service
              - match:
                  prefix: "/"
                route:
                  cluster: web_service
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: users_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: users_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: users-service.example.com
                port_value: 80
  
  - name: products_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: products_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: products-service.example.com
                port_value: 80
  
  - name: orders_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: orders_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: orders-service.example.com
                port_value: 80
  
  - name: web_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: web_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: web-service.example.com
                port_value: 80
```

### 2. gRPCプロキシ

gRPCサービスのプロキシ設定例：

```yaml
static_resources:
  listeners:
  - name: listener_grpc
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 9090
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: grpc_json
          codec_type: AUTO
          route_config:
            name: grpc_route
            virtual_hosts:
            - name: grpc_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: grpc_service
                  timeout: 60s
          http_filters:
          - name: envoy.filters.http.grpc_web
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  
  clusters:
  - name: grpc_service
    connect_timeout: 0.25s
    type: LOGICAL_DNS
    lb_policy: ROUND_ROBIN
    http2_protocol_options: {}  # HTTP/2を有効化（gRPCに必要）
    load_assignment:
      cluster_name: grpc_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: grpc-service.example.com
                port_value: 50051
```

### 3. 認証プロキシ

JWT認証を使用したプロキシ設定例：

```yaml
static_resources:
  listeners:
  - name: listener_http
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match:
                  prefix: "/api/"
                route:
                  cluster: api_service
          http_filters:
          - name: envoy.filters.http.jwt_authn
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.jwt_authn.v3.JwtAuthentication
              providers:
                provider1:
                  issuer: https://auth.example.com
                  audiences:
                  - api.example.com
                  remote_jwks:
                    http_uri:
                      uri: https://auth.example.com/.well-known/jwks.json
                      cluster: jwks_cluster
                      timeout: 5s
                    cache_duration:
                      seconds: 300
              rules:
              - match:
                  prefix: /api/
                requires:
                  provider_name: provider1
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  
  clusters:
  - name: api_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: api_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: api.example.com
                port_value: 80
  
  - name: jwks_cluster
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: jwks_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: auth.example.com
                port_value: 443
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: auth.example.com
```

## ベストプラクティス

### 1. 設定の検証

設定ファイルをデプロイする前に、`--mode validate`オプションを使用して検証することをお勧めします：

```bash
envoy --mode validate -c envoy.yaml
```

### 2. 段階的なデプロイ

設定変更を本番環境に適用する際は、カナリアデプロイメントを使用して、一部のトラフィックのみに新しい設定を適用することをお勧めします。

### 3. 監視とロギング

適切な監視とロギングを設定して、問題を早期に検出できるようにしましょう：

```yaml
static_resources:
  listeners:
  - name: listener_http
    # ...
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          # ...
          access_log:
          - name: envoy.access_loggers.file
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
              path: /var/log/envoy/access.log
              format: "[%START_TIME%] %REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL% %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% \"%REQ(X-FORWARDED-FOR)%\" \"%REQ(USER-AGENT)%\" \"%REQ(X-REQUEST-ID)%\" \"%REQ(:AUTHORITY)%\"\n"
```

### 4. リソース制限

リソース使用量を制限して、DoS攻撃からシステムを保護しましょう：

```yaml
static_resources:
  listeners:
  - name: listener_http
    # ...
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          # ...
          http_filters:
          - name: envoy.filters.http.buffer
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
              max_request_bytes: 16384  # 16KB
```

## まとめ

Envoyの設定は非常に柔軟で強力ですが、複雑になる可能性もあります。このガイドで説明した基本的な構造と例を参考に、ユースケースに合わせた設定を作成してください。より詳細な情報については、[Envoyの公式ドキュメント](https://www.envoyproxy.io/docs/envoy/latest/configuration/configuration)を参照してください。
