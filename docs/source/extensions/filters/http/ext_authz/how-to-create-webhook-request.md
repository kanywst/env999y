# How to create webhook request

- [How to create webhook request](#how-to-create-webhook-request)
  - [Sequence](#sequence)
  - [void RawHttpClientImpl::check Sequence](#void-rawhttpclientimplcheck-sequence)
  - [Implementation](#implementation)
    - [1. 認可リクエストの構築と送信の起点](#1-認可リクエストの構築と送信の起点)
    - [2. ヘッダーの具体的な操作箇所](#2-ヘッダーの具体的な操作箇所)

## Sequence

```mermaid
sequenceDiagram
    participant C as クライアント
    participant E as Envoy (ExtAuthz Filter)
    participant A as 認可サーバー (AuthZ Service)
    participant S as アップストリームサービス (Upstream Service)

    C->>E: 1. オリジナルリクエスト (POST /client2extauthz)
    activate E
    Note over E: ExtAuthz フィルターが処理を開始

    E->>A: 2. 認可 Webhook リクエスト作成・送信
    Note right of E: - :method, Authorization ヘッダーをコピー<br/>- :path, :authority を認可サーバー向けに上書き<br/>- content-length: 0 (ボディなし)<br/>- x-athenz-action: POST を追加
    activate A
    A-->>E: 3. 認可応答 (200 OK)
    deactivate A
    Note over E: 認可成功

    E->>S: 4. オリジナルリクエストをアップストリームにルーティング (POST /client2extauthz)
    activate S
    S-->>E: 5. サービス応答
    deactivate S

    E-->>C: 6. クライアントに応答を返送
    deactivate E
```

## void RawHttpClientImpl::check Sequence


```mermaid
sequenceDiagram
    participant C as Caller (ExtAuthz Filter)
    participant I as RawHttpClientImpl::check()
    participant H as HeaderMap (AuthZ Req)
    participant T as ThreadLocalCluster
    participant A as AuthZ Server

    C->>I: 1. check(CheckRequest R, ...) 呼び出し
    activate I
    Note over I: **フェーズ 1: ヘッダーマップの初期化**

    I->>I: 2. R からボディの長さ(request_length)を計算
    I->>H: 3. Content-Length ヘッダーを初期設定
    Note right of H: request_length が 0 なら '0' に設定

    Note over I: **フェーズ 2: オリジナルヘッダーのコピー**
    loop R.headers() の各ヘッダーについて
        I->>I: 4. Content-Length をスキップ
        I->>H: 5. 残りのヘッダーをコピー (Path は prefix を前置)
    end

    I->>I: 6. カスタム/動的ヘッダー評価・追加
    Note right of I: config_->requestHeaderParser() を実行 (e.g., x-athenz-action: POST がここで追加される)

    I->>I: 7. Http::RequestMessage を構築 (ヘッダーHを使用)
    alt request_length > 0
        I->>I: 8. R.body をメッセージボディに追加
    end

    Note over I: **フェーズ 3: 宛先クラスターのチェックと送信**
    I->>T: 9. config_->cluster() に基づき ThreadLocalCluster を取得
    alt Cluster が見つからない (CDS削除など)
        T-->>I: nullptr
        I->>C: 10. onComplete(Error Response) をコールバック
        deactivate I
    else Cluster が存在する
        T-->>I: Cluster オブジェクトを返す
        I->>I: 11. AsyncClient Options を設定 (Timeout, Tracing, Retry)
        I->>A: 12. httpAsyncClient().send(message, *this, options)
    end
    Note over A, C: (認可サーバーからの応答は非同期で別のコールバックで処理)
```

## Implementation

### 1. 認可リクエストの構築と送信の起点

この処理全体を担う主要なクラスは、`ext_authz` フィルターが内部的に利用する HTTP クライアントの実装です。

- **ファイル**: `source/extensions/filters/http/ext_authz/raw_http_client_impl.cc`
- **関数**: `RawHttpClientImpl::check(RequestCallbacks& callbacks, const envoy::service::ext_authz::v3::CheckRequest& request, Tracing::Span& parent_span, const StreamInfo::StreamInfo& stream_info)`

この `check` 関数内で、以下のステップが実行されます。

1. 認可リクエストを作成するために必要なすべての情報（元のリクエストヘッダー、ボディ、`ext_authz` 設定）が渡されます。
1. この関数が、**アップストリーム（認可サーバー）への接続プール**を見つけ、新しいストリームを作成し、リクエストのエンコードと送信をトリガーします。

### 2. ヘッダーの具体的な操作箇所

ヘッダーの具体的な操作は、`check` 関数内で実行されるロジックと、設定ファイルに基づいています。

| 操作内容 | 実装の具体的な処理/設定 | 補足 |
| :--- | :--- | :--- |
| **`:method`, `Authorization` ヘッダーをコピー** | `check` 関数内で、**オリジナルのリクエストヘッダーをループしてコピー**するロジック。 | ここで、`http_request.headers()` のすべての非禁止ヘッダー（`:method` などを含む）が新しい AuthZ リクエストヘッダーマップにコピーされます。 |
| **`:path`, `:authority` を認可サーバー向けに上書き** | `check` 関数内で、`ext_authz` フィルターの設定に基づき、**ターゲットクラスター (`authorization-sidecar`) の設定**から取得した情報を使用して、これらの**擬似ヘッダーを新しい値で上書き**します。 | `:path` は設定されている `/extauthz` に、`:authority` は設定されている `authorizer.athenz.svc.cluster.local` になります。 |
| **`content-length: 0` (ボディなし)** | `ext_authz` 設定で `with_request_body` がないため、`check` 関数内でリクエストボディがないと判断され、ヘッダーに **`content-length: 0`** が追加されます。 |
| **`x-athenz-action: POST` を追加** | `http_service` の設定にある `authorization_request.headers_to_add` の処理。 | 設定されている値 `x-athenz-action: "%REQ(:METHOD)%"` に基づき、このカスタムヘッダーを新しいリクエストヘッダーマップに**追加**します。 |
