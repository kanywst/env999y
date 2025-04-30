# Envoy 入門ガイド

- [Envoy 入門ガイド](#envoy-入門ガイド)
  - [前提条件](#前提条件)
  - [インストール方法](#インストール方法)
    - [1. Dockerを使用する方法（推奨）](#1-dockerを使用する方法推奨)
    - [2. バイナリをダウンロードする方法](#2-バイナリをダウンロードする方法)
    - [3. パッケージマネージャーを使用する方法](#3-パッケージマネージャーを使用する方法)
      - [Ubuntu/Debian](#ubuntudebian)
      - [CentOS/RHEL](#centosrhel)
  - [基本的な設定](#基本的な設定)
    - [主要な設定コンポーネント](#主要な設定コンポーネント)
  - [基本的な使用例](#基本的な使用例)
    - [1. シンプルなHTTPプロキシ](#1-シンプルなhttpプロキシ)
    - [2. HTTPSプロキシ（TLS終端）](#2-httpsプロキシtls終端)
  - [Envoyの実行](#envoyの実行)
  - [管理インターフェースの使用](#管理インターフェースの使用)
  - [基本的なトラブルシューティング](#基本的なトラブルシューティング)
    - [1. 接続の問題](#1-接続の問題)
    - [2. 一般的なエラー](#2-一般的なエラー)
  - [次のステップ](#次のステップ)

このガイドでは、Envoyプロキシの基本的な使用方法について説明します。Envoyを初めて使用する方向けに、インストール方法から基本的な設定、実行方法までを解説します。

## 前提条件

- Linux、macOS、またはWindowsマシン
- Docker（推奨）または直接インストール用の環境
- 基本的なネットワークとプロキシの概念の理解

## インストール方法

Envoyをインストールするには複数の方法があります。ここでは最も一般的な方法を紹介します。

### 1. Dockerを使用する方法（推奨）

Dockerを使用すると、Envoyを簡単に実行できます。

```bash
# 公式Dockerイメージをプル
docker pull envoyproxy/envoy:v1.28.0

# 設定ファイルを用意するディレクトリを作成
mkdir -p envoy-config

# 基本的な設定ファイルを作成
cat > envoy-config/envoy.yaml << EOF
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
                  prefix: "/"
                route:
                  host_rewrite_literal: www.envoyproxy.io
                  cluster: service_envoyproxy_io

  clusters:
  - name: service_envoyproxy_io
    connect_timeout: 30s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: service_envoyproxy_io
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: www.envoyproxy.io
                port_value: 443
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: www.envoyproxy.io

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
EOF

# Envoyを実行
docker run --rm -d \
  --name envoy \
  -p 9901:9901 \
  -p 10000:10000 \
  -v $(pwd)/envoy-config:/etc/envoy \
  envoyproxy/envoy:v1.28.0 \
  /usr/local/bin/envoy -c /etc/envoy/envoy.yaml
```

### 2. バイナリをダウンロードする方法

公式のリリースページから直接バイナリをダウンロードすることもできます。

```bash
# Linuxの場合
curl -L https://func-e.io/install.sh | bash -s -- -b /usr/local/bin
func-e use 1.28.0
cp ~/.func-e/versions/1.28.0/bin/envoy /usr/local/bin/
```

### 3. パッケージマネージャーを使用する方法

#### Ubuntu/Debian

```bash
sudo apt update
sudo apt install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -sL 'https://deb.dl.getenvoy.io/public/gpg.8115BA8E629CC074.key' | sudo gpg --dearmor -o /usr/share/keyrings/getenvoy-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy-keyring.gpg] https://deb.dl.getenvoy.io/public/deb/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/getenvoy.list
sudo apt update
sudo apt install getenvoy-envoy
```

#### CentOS/RHEL

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://getenvoy.io/linux/rpm/tetrate-getenvoy.repo
sudo yum install -y getenvoy-envoy
```

## 基本的な設定

Envoyの設定は主にYAML形式で記述します。基本的な設定ファイルの構造は以下の通りです：

```yaml
static_resources:
  listeners:      # トラフィックを受信するリスナー
  clusters:       # 接続先のバックエンドサービス
admin:            # 管理インターフェース
```

### 主要な設定コンポーネント

1. **リスナー (Listeners)**
   - トラフィックを受信するポートとアドレス
   - フィルターチェーン（トラフィック処理のパイプライン）

2. **クラスター (Clusters)**
   - バックエンドサービスのグループ
   - ロードバランシング設定
   - ヘルスチェック設定

3. **ルート (Routes)**
   - リクエストをどのクラスターに転送するかのルール
   - パスベース、ヘッダーベースなどのマッチング

4. **フィルター (Filters)**
   - リクエスト/レスポンスの処理ロジック
   - 認証、レート制限、変換などの機能

5. **管理インターフェース (Admin)**
   - 統計情報、設定、ログレベルなどの管理機能

## 基本的な使用例

### 1. シンプルなHTTPプロキシ

以下の設定は、ポート8080でリクエストを受け付け、example.comにプロキシします：

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
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: service_example

  clusters:
  - name: service_example
    connect_timeout: 5s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: service_example
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: example.com
                port_value: 80

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
```

### 2. HTTPSプロキシ（TLS終端）

クライアントからのHTTPS接続を終端し、バックエンドにHTTPで接続する例：

```yaml
static_resources:
  listeners:
  - name: listener_https
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8443
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
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_https
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: service_example

  clusters:
  - name: service_example
    connect_timeout: 5s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: service_example
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: example.com
                port_value: 80

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
```

## Envoyの実行

設定ファイルを用意したら、Envoyを実行します：

```bash
# Dockerを使用する場合
docker run --rm \
  -p 8080:8080 \
  -p 9901:9901 \
  -v $(pwd)/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.28.0

# バイナリを直接実行する場合
envoy -c envoy.yaml
```

## 管理インターフェースの使用

Envoyは管理インターフェースを提供しており、デフォルトではポート9901で利用できます。ブラウザで以下のURLにアクセスすると、様々な情報を確認できます：

- http://localhost:9901/ - 管理インターフェースのホームページ
- http://localhost:9901/stats - 統計情報
- http://localhost:9901/config_dump - 現在の設定
- http://localhost:9901/clusters - クラスターの状態
- http://localhost:9901/listeners - リスナーの状態
- http://localhost:9901/server_info - サーバー情報

## 基本的なトラブルシューティング

### 1. 接続の問題

Envoyが正しく接続できない場合は、以下を確認してください：

```bash
# ログを確認
docker logs envoy

# クラスターの状態を確認
curl http://localhost:9901/clusters

# 設定をダンプ
curl http://localhost:9901/config_dump
```

### 2. 一般的なエラー

- **Address already in use**: 指定したポートが既に使用されています
- **Failed to load config**: 設定ファイルに問題があります
- **Upstream connect error**: バックエンドサービスに接続できません

## 次のステップ

基本的な使用方法を理解したら、以下の高度な機能を試してみましょう：

1. **動的設定**: xDS APIを使用した動的設定
2. **高度なロードバランシング**: 様々なロードバランシングアルゴリズム
3. **フィルター**: カスタムフィルターの追加
4. **可観測性**: トレーシングと監視の設定
5. **サーキットブレーキング**: 障害からの保護

詳細については、[Envoyの公式ドキュメント](https://www.envoyproxy.io/docs/envoy/latest/)を参照してください。
