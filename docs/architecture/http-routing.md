# HTTP ルーティングのシーケンス

- [HTTP ルーティングのシーケンス](#http-ルーティングのシーケンス)
  - [主要なルーティング機能の解説](#主要なルーティング機能の解説)
    - [1. ルーティングの意思決定 (Route Matching)](#1-ルーティングの意思決定-route-matching)
    - [2. リクエスト操作 (Rewriting \& Redirection)](#2-リクエスト操作-rewriting--redirection)
    - [3. 高度な転送ポリシー (Policies)](#3-高度な転送ポリシー-policies)
    - [4. Direct Responses](#4-direct-responses)

ダウンストリームクライアントからのHTTPリクエストがEnvoyに到達し、アップストリームサーバーへ転送されるまでの主要なステップを示します。

```mermaid
sequenceDiagram
    participant Downstream
    participant HCM as HTTP Connection Manager
    participant HttpFilters as HTTP Filters (Other)
    participant RouterFilter as Router Filter
    participant RouteTable as Route Table/Virtual Hosts
    participant ClusterManager as Cluster Manager
    participant UpstreamPool as Connection Pool
    participant Upstream as Upstream Host

    Downstream->>HCM: 1. HTTP Request 送信
    activate HCM
    HCM->>HttpFilters: 2. L7フィルターチェーン実行 (認証, レート制限など)
    activate HttpFilters
    HttpFilters->>RouterFilter: 3. ルーターフィルターへ制御移行
    deactivate HttpFilters

    RouterFilter->>RouteTable: 4. ルーティングマッチング
    activate RouteTable
    Note over RouteTable: 4a. Virtual Host / Route Scope を決定
    RouteTable->>RouteTable: 4b. パス/ヘッダー/Regexマッチングで Route Rule を特定
    RouteTable-->>RouterFilter: 5. マッチした Route Rule を返却 (Target Cluster, Policy, Rewrite情報を含む)
    deactivate RouteTable

    RouterFilter->>RouterFilter: 6. 経路操作/ポリシー適用
    Note over RouterFilter: 6a. パス/ホストの書き換え (Path/Host Rewrite)<br>6b. リトライポリシー/タイムアウト/ヘッジングを適用

    RouterFilter->>ClusterManager: 7. アップストリームホスト選択 (Load Balancing)
    activate ClusterManager
    ClusterManager->>UpstreamPool: 8. ターゲットクラスターの接続プールからホストを選択
    ClusterManager-->>RouterFilter: 9. 選択された Upstream Host (IP:Port) を返却
    deactivate ClusterManager

    RouterFilter->>Upstream: 10. Request を Upstream Host へ転送 (プロキシ)
    activate Upstream
    Upstream-->>RouterFilter: 11. Response 返却
    deactivate Upstream

    RouterFilter->>HCM: 12. Response 処理完了 (リトライ判定など)
    HCM-->>Downstream: 13. Response 返却
    deactivate HCM
```

## 主要なルーティング機能の解説

### 1. ルーティングの意思決定 (Route Matching)

Envoyのルーティングは、**ルートテーブル**（`Route Table`）に基づいて行われます。

- **Virtual Hosts & Clusters**:
  - ドメイン名や `:authority` ヘッダーに基づいて、まず**Virtual Host** を決定します。
  - この Virtual Host 内に、具体的なルーティングルール（**Route Rule**）が定義されています。
- **マッチング基準**:
  - リクエストの **パス** (`/path` や `/prefix`)、**ヘッダー**、**クエリパラメータ**、**正規表現**など、多岐にわたる条件でルールを照合します。
- **Route Scope (SRDS)**:
  - 大規模な設定において、リクエストヘッダーなどの動的なキーに基づいて、検索対象のルートテーブルを絞り込む（スコープを制限する）高度な機能です。
  - これにより、マッチングの効率（**O(log N)** に近いサブ線形マッチング）が向上します。

### 2. リクエスト操作 (Rewriting & Redirection)

- **Path/Prefix Rewriting**:
  - アップストリームにリクエストを転送する直前に、リクエストのパスやプレフィックスを変更できます。
  - 例えば、外部からは `/v1/users` でも、内部サービスには `/users` として転送することが可能です。
- **Redirection**:
  - ルートにマッチしたリクエストを、指定された別のURLやTLS (`https`) へリダイレクトするよう、クライアントに指示できます。

### 3. 高度な転送ポリシー (Policies)

Envoyのルーターは、単にリクエストを転送するだけでなく、信頼性とパフォーマンスを高めるための高度なポリシーを適用します。

- **タイムアウト & リトライ (Retries)**:
  - **最大リトライ回数**や、ネットワーク障害、特定のステータスコード（例：`5xx`）などの**リトライ条件**を設定できます。
- **リトライ予算 (Retry Budgets)**:
  - リトライが元のトラフィックを過剰に増加させ、サービスに負荷をかける（**リトライストーム**）のを防ぐため、リトライの割合に上限を設定します。
- **リクエストヘッジング (Request Hedging)**:
  - **リクエストがタイムアウト**した場合、元のリクエストをキャンセルせずに、**追加で別のアップストリームホストにリトライリクエストを送信**し、最初に返ってきた「良い」レスポンスを採用する手法です。
  - これは遅延を最小限に抑えるのに役立ちます。
- **トラフィックシフティング/スプリッティング**:
  - 重み付け (`weight/percentage`) に基づいて、トラフィックを複数のアップストリームクラスターに分散させ、カナリアリリースや A/B テストなどを実現します。

### 4. Direct Responses

- ルーターフィルターは、アップストリームへのプロキシを行わず、Envoy自体が直接 HTTP レスポンス（ステータスコードやボディ）を返すように設定することも可能です。
  - これは、リダイレクトや簡単なエラー応答を効率的に処理するために使用されます。
