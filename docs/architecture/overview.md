# Envoy アーキテクチャ概要

- [Envoy アーキテクチャ概要](#envoy-アーキテクチャ概要)
  - [Envoyとは](#envoyとは)
  - [設計目標](#設計目標)
  - [コアコンポーネント](#コアコンポーネント)
    - [リスナー](#リスナー)
    - [フィルターチェーン](#フィルターチェーン)
    - [HTTP connection manager](#http-connection-manager)
    - [HTTPフィルター](#httpフィルター)
    - [クラスター](#クラスター)
    - [ロードバランサー](#ロードバランサー)
    - [エンドポイント](#エンドポイント)
  - [スレッディングモデル](#スレッディングモデル)
  - [動的設定](#動的設定)
  - [可観測性](#可観測性)
  - [ホットリスタート](#ホットリスタート)

## Envoyとは

Envoyは、大規模な現代的サービス指向アーキテクチャのために設計された、L7プロキシおよび通信バスです。プロジェクトは以下の信念に基づいています：

> ネットワークは透過的であるべきである。問題が発生した場合、アプリケーションコードを変更するのではなく、ネットワークとその問題を簡単に理解できるようにすべきである。

実際には、この目標を達成することは非常に困難です。Envoyはこの問題に対して以下のアプローチを取ります：

## 設計目標

Envoyは以下の設計目標を持っています：

1. **プロセス外アーキテクチャ**: Envoyはアプリケーションとは別のプロセスとして実行されます。これにより、任意の言語やフレームワークで書かれたアプリケーションと連携できます。

2. **モダンなC++コードベース**: Envoyは高性能なC++14で書かれており、メモリ使用量が少なく、高速です。

3. **L3/L4フィルター**: Envoyは基本的にL3/L4（TCP/UDP）ネットワークプロキシとして機能します。様々なL4フィルターのチェーンをリスナーに接続でき、TCP/UDPトラフィックを処理できます。

4. **HTTP L7フィルター**: HTTPはモダンなWebアプリケーションの主要なプロトコルであるため、Envoyは強力なHTTP L7フィルターレイヤーを提供します。

5. **ファーストクラスHTTP/2サポート**: HTTP/1.1とHTTP/2の両方をサポートし、両プロトコル間の透過的なプロキシをサポートします。

6. **高度なロードバランシング**: 自動再試行、サーキットブレーキング、グローバルレート制限、シャドウリクエスト、ゾーンローカルロードバランシングなどの高度な機能をサポートします。

## コアコンポーネント

Envoyのアーキテクチャは以下の主要コンポーネントで構成されています：

```mermaid
graph TD
    A[リスナー] --> B[フィルターチェーン]
    B --> C[HTTP接続マネージャ]
    C --> D[HTTPフィルター]
    D --> E[ルーター]
    E --> F[クラスター]
    F --> G[ロードバランサー]
    G --> H[エンドポイント]
```

### リスナー

リスナーはEnvoyがトラフィックを受信するネットワークの場所（IPアドレスとポート）です。Envoyは複数のリスナーを持つことができ、それぞれが異なるプロトコルやフィルターチェーンを持つことができます。

### フィルターチェーン

```mermaid
sequenceDiagram
    participant Downstream
    participant Listener
    participant ListenerFilters
    participant FilterChainMatch
    participant NetworkFilters
    participant Upstream

    Downstream->>Listener: 1. 新しい接続要求 (SYN)
    Listener->>Listener: 2. 接続の受け付け (Accept)
    Listener->>ListenerFilters: 3. リスナーフィルターの実行
    activate ListenerFilters
    ListenerFilters->>ListenerFilters: 3a. TLSハンドシェイク, PROXYプロトコル処理など
    ListenerFilters-->>Listener: 3b. 処理完了/メタデータ付与
    deactivate ListenerFilters
    Listener->>FilterChainMatch: 4. フィルターチェーンのマッチング
    FilterChainMatch->>FilterChainMatch: 4a. 接続メタデータ(SNI, IP範囲など)に基づいて最適なFilterChainを選択
    FilterChainMatch-->>Listener: 4b. 選択されたFilterChainを取得
    Listener->>NetworkFilters: 5. ネットワークフィルターの実行 (Read/Write)
    activate NetworkFilters
    NetworkFilters->>NetworkFilters: 5a. フィルターの連鎖処理 (e.g., Rate Limit, HTTP Connection Manager)
    alt L4 (TCP Proxy) の場合
        NetworkFilters->>Upstream: 5b. TCP ProxyがUpstreamへの接続を確立
        Upstream-->>NetworkFilters: 5c. Upstreamからの応答
        NetworkFilters-->>Downstream: 5d. Downstreamへのデータ転送
    else L7 (HTTP Connection Manager) の場合
        NetworkFilters->>NetworkFilters: 5b'. L7処理 (ルーティング, ヘッダー操作など)
        NetworkFilters->>Upstream: 5c'. Upstreamへのリクエスト
        Upstream-->>NetworkFilters: 5d'. Upstreamからのレスポンス
        NetworkFilters-->>Downstream: 5e'. Downstreamへのレスポンス
    end
    deactivate NetworkFilters
```

各リスナーは一連のフィルターを持ち、これらのフィルターがリクエストを処理します。フィルターには以下の種類があります：

- **リスナーフィルター**: 新しい接続が確立されたときに実行されます
- **ネットワークフィルター**: L4（TCP/UDP）レベルで動作します
- **HTTPフィルター**: L7（HTTP）レベルで動作します

### HTTP connection manager

```mermaid
sequenceDiagram
    participant Downstream
    participant Listener
    participant NetworkFilterChain
    participant HttpConnectionManager
    participant HttpFilter1
    participant RouterFilter
    participant Upstream

    Downstream->>Listener: 1. TCP接続確立
    Listener->>NetworkFilterChain: 2. L4フィルターチェーン開始
    Note over NetworkFilterChain: (例: TLSフィルター、接続制限フィルター)
    NetworkFilterChain->>HttpConnectionManager: 3. HTTP Connection Manager (HCM) に制御移行
    activate HttpConnectionManager
    HttpConnectionManager->>HttpConnectionManager: 4. L4ストリームをHTTPリクエストにデコード
    HttpConnectionManager->>HttpFilter1: 5. L7 HTTPフィルターチェーン開始
    activate HttpFilter1
    HttpFilter1->>HttpFilter1: 5a. HTTPフィルター処理 (例: 認証/レート制限)
    HttpFilter1->>RouterFilter: 6. ルーターフィルターに制御移行 (通常はチェーンの最後)
    activate RouterFilter
    RouterFilter->>RouterFilter: 7. ルーティング処理 (Virtual Host/Route Match)
    RouterFilter->>Upstream: 8. アップストリームへリクエスト送信
    Upstream-->>RouterFilter: 9. アップストリームからレスポンス
    RouterFilter-->>HttpFilter1: 10. HTTPフィルターチェーン逆順処理
    HttpFilter1-->>HttpConnectionManager: 11. 処理完了
    deactivate RouterFilter
    deactivate HttpFilter1
    HttpConnectionManager->>HttpConnectionManager: 12. HTTPレスポンスをL4ストリームにエンコード
    HttpConnectionManager-->>NetworkFilterChain: 13. L4フィルターチェーンに戻る
    deactivate HttpConnectionManager
    NetworkFilterChain-->>Downstream: 14. ダウンストリームへレスポンス送信
```

HTTP接続マネージャーは特殊なネットワークフィルターで、HTTP/1.1、HTTP/2、HTTP/3プロトコルを処理し、HTTPフィルターチェーンを管理します。

### HTTPフィルター

HTTPフィルターはHTTPリクエストとレスポンスを処理します。一般的なフィルターには以下があります：

- router: バックエンドサービスへのリクエストのルーティング
- RBAC: ロールベースのアクセス制御
- Lua: Luaスクリプトの実行
- gRPC-JSON: gRPCとJSONの間の変換
- レート制限: リクエストのレート制限

### クラスター

クラスターはEnvoyが接続するバックエンドサービスのグループです。各クラスターには以下の設定があります：

- サービスディスカバリ方法（静的、DNS、EDS）
- ロードバランシングポリシー
- ヘルスチェック設定
- サーキットブレーカー設定

### ロードバランサー

ロードバランサーはクラスター内のエンドポイント間でトラフィックを分散させる方法を決定します。サポートされているアルゴリズムには以下があります：

- ラウンドロビン
- 最小接続数
- リングハッシュ（一貫性のあるハッシュ）
- ランダム
- マルチプライオリティ

### エンドポイント

エンドポイントは実際のバックエンドサービスのインスタンスです。IPアドレスとポートで識別されます。

## スレッディングモデル

Envoyは以下のスレッドモデルを採用しています：

```mermaid
graph LR
    A[メインスレッド] --> B[ワーカースレッド 1]
    A --> C[ワーカースレッド 2]
    A --> D[...]
    A --> E[ワーカースレッド N]
```

- **シングルプロセス、マルチスレッドアーキテクチャ**: 1つのEnvoyプロセスが複数のスレッドを実行します
- **スレッドローカルストレージ**: 各ワーカースレッドは独自の接続プールとイベントループを持ちます
- **ノンブロッキングI/O**: すべてのI/Oはノンブロッキングです
- **接続所有権**: 接続は単一のワーカースレッドによって所有され、そのスレッドでのみ処理されます

## 動的設定

```mermaid
sequenceDiagram
    participant Envoy
    participant ControlPlane
    
    Envoy->>ControlPlane: 1. 初期接続 (gRPCストリーム確立)
    
    ControlPlane-->>Envoy: 2. 接続確認 (ACK)
    
    Envoy->>ControlPlane: 3. CDS (Cluster Discovery Service) 要求
    activate ControlPlane
    ControlPlane->>Envoy: 4. Cluster リソース応答 (Cluster A, B など)
    deactivate ControlPlane
    
    Envoy->>ControlPlane: 5. LDS (Listener Discovery Service) 要求
    activate ControlPlane
    ControlPlane->>Envoy: 6. Listener リソース応答 (Listener 80, 443 など)
    deactivate ControlPlane
    
    Envoy->>ControlPlane: 7. RDS (Route Discovery Service) 要求
    activate ControlPlane
    ControlPlane->>Envoy: 8. Route Configuration リソース応答
    deactivate ControlPlane
    
    Envoy->>ControlPlane: 9. EDS (Endpoint Discovery Service) 要求 (Cluster A, B のエンドポイント情報)
    activate ControlPlane
    ControlPlane->>Envoy: 10. Endpoint リソース応答 (IP:Port リスト)
    deactivate ControlPlane
    
    Note over Envoy,ControlPlane: --- 設定の変更が発生した場合 ---
    
    ControlPlane->>Envoy: 11. Endpoint の変更通知 (EDS Push)
    activate ControlPlane
    ControlPlane->>Envoy: 12. 新しい Endpoint リソース応答 (IP:Port リスト更新)
    deactivate ControlPlane
    
    Envoy->>ControlPlane: 13. ACK/NACK (変更の適用確認)
    
    Note over Envoy: Envoyは実行中の接続に影響を与えずに設定を動的に更新する
```

Envoyは動的設定をサポートしており、実行中に設定を更新できます。これは以下のAPIを通じて行われます：

- **リスナーディスカバリーサービス (LDS)**: ダウンストリームからの接続を待ち受けるリスナーの動的設定（ポート、フィルターチェーンなど）。
- **ルートディスカバリーサービス (RDS)**: HTTPルートの動的設定（ホスト名、パスベースのルーティングルール）
- **クラスターディスカバリーサービス (CDS)**: アップストリームクラスターの動的設定（負荷分散ポリシーなど）
- **エンドポイントディスカバリーサービス (EDS)**: CDSで定義されたクラスターのエンドポイント（実際のサーバーIP/Portリスト）の動的設定
- **シークレットディスカバリーサービス (SDS)**: TLS証明書の動的設定

## 可観測性

Envoyは以下の可観測性機能を提供します：

- **統計情報**: 広範な統計情報を生成し、様々なシンクに送信できます（statsd、Prometheus等）
- **分散トレーシング**: Zipkin、Jaeger、Datadog、OpenCensusなどのトレーシングシステムと統合
- **アクセスログ**: カスタマイズ可能なアクセスログ形式
- **管理インターフェース**: 実行時の統計情報、設定、ログレベルの変更などを提供

## ホットリスタート

Envoyはゼロダウンタイムでの再起動をサポートしています。新しいプロセスが起動すると、古いプロセスから以下の情報を引き継ぎます：

- リスナーソケット
- 既存の接続
- 統計情報

これにより、設定の更新やバイナリのアップグレードをダウンタイムなしで行うことができます。
