# Envoy 拡張ガイド

このドキュメントでは、Envoyの拡張機能を開発する方法について説明します。Envoyは高度に拡張可能なアーキテクチャを持ち、様々なポイントでカスタム機能を追加できます。

## 拡張ポイント

Envoyは以下の主要な拡張ポイントを提供しています：

1. **HTTPフィルター**: HTTPリクエスト/レスポンスの処理
2. **ネットワークフィルター**: TCP/UDPトラフィックの処理
3. **リスナーフィルター**: 新しい接続の処理
4. **アクセスロガー**: アクセスログの生成
5. **トレーサー**: 分散トレーシング
6. **統計シンク**: 統計情報の出力
7. **ヘルスチェッカー**: カスタムヘルスチェック
8. **リソースモニター**: リソース使用量の監視
9. **トランスポートソケット**: TLSなどの接続レベルの暗号化

## 拡張機能の開発方法

Envoyの拡張機能を開発するには、主に以下の2つの方法があります：

1. **コア拡張機能**: C++でコードを書き、Envoyのコードベースに直接統合する方法
2. **WASM拡張機能**: WebAssembly（WASM）を使用して、ランタイムにロード可能な拡張機能を作成する方法

## コア拡張機能の開発

### 1. 開発環境のセットアップ

[ビルドガイド](building.md)に従って、Envoyの開発環境をセットアップします。

### 2. 拡張機能の基本構造

例として、シンプルなHTTPフィルターを作成する手順を示します：

#### ディレクトリ構造

```
source/extensions/filters/http/my_filter/
├── BUILD
├── config.cc
├── config.h
├── filter.cc
└── filter.h
```

#### フィルターの実装

`filter.h`:

```cpp
#pragma once

#include "envoy/http/filter.h"
#include "source/common/common/logger.h"
#include "source/extensions/filters/http/common/pass_through_filter.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace MyFilter {

/**
 * 実際のフィルター実装
 */
class Filter : public Http::PassThroughFilter {
public:
  Filter();
  ~Filter() override;

  // Http::StreamFilterBase
  void onDestroy() override;

  // Http::StreamDecoderFilter
  Http::FilterHeadersStatus decodeHeaders(Http::RequestHeaderMap& headers, bool end_stream) override;
  Http::FilterDataStatus decodeData(Buffer::Instance& data, bool end_stream) override;
  Http::FilterTrailersStatus decodeTrailers(Http::RequestTrailerMap& trailers) override;

  // Http::StreamEncoderFilter
  Http::FilterHeadersStatus encodeHeaders(Http::ResponseHeaderMap& headers, bool end_stream) override;
  Http::FilterDataStatus encodeData(Buffer::Instance& data, bool end_stream) override;
  Http::FilterTrailersStatus encodeTrailers(Http::ResponseTrailerMap& trailers) override;

private:
  // フィルター固有の状態やデータ
};

} // namespace MyFilter
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
```

`filter.cc`:

```cpp
#include "source/extensions/filters/http/my_filter/filter.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace MyFilter {

Filter::Filter() {}
Filter::~Filter() {}

void Filter::onDestroy() {}

Http::FilterHeadersStatus Filter::decodeHeaders(Http::RequestHeaderMap& headers, bool end_stream) {
  // リクエストヘッダーの処理
  return Http::FilterHeadersStatus::Continue;
}

Http::FilterDataStatus Filter::decodeData(Buffer::Instance& data, bool end_stream) {
  // リクエストボディの処理
  return Http::FilterDataStatus::Continue;
}

Http::FilterTrailersStatus Filter::decodeTrailers(Http::RequestTrailerMap& trailers) {
  // リクエストトレイラーの処理
  return Http::FilterTrailersStatus::Continue;
}

Http::FilterHeadersStatus Filter::encodeHeaders(Http::ResponseHeaderMap& headers, bool end_stream) {
  // レスポンスヘッダーの処理
  return Http::FilterHeadersStatus::Continue;
}

Http::FilterDataStatus Filter::encodeData(Buffer::Instance& data, bool end_stream) {
  // レスポンスボディの処理
  return Http::FilterDataStatus::Continue;
}

Http::FilterTrailersStatus Filter::encodeTrailers(Http::ResponseTrailerMap& trailers) {
  // レスポンストレイラーの処理
  return Http::FilterTrailersStatus::Continue;
}

} // namespace MyFilter
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
```

#### ファクトリーとコンフィグの実装

`config.h`:

```cpp
#pragma once

#include "envoy/server/filter_config.h"

#include "source/extensions/filters/http/common/factory_base.h"
#include "source/extensions/filters/http/my_filter/filter.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace MyFilter {

/**
 * フィルター設定の定義
 */
struct FilterConfig {
  // フィルター固有の設定
};

/**
 * フィルターファクトリーの実装
 */
class Factory : public Common::FactoryBase<FilterConfig> {
public:
  Factory() : FactoryBase("envoy.filters.http.my_filter") {}

private:
  Http::FilterFactoryCb createFilterFactoryFromProtoTyped(
      const FilterConfig& proto_config,
      const std::string& stats_prefix,
      Server::Configuration::FactoryContext& context) override;
};

} // namespace MyFilter
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
```

`config.cc`:

```cpp
#include "source/extensions/filters/http/my_filter/config.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace MyFilter {

Http::FilterFactoryCb Factory::createFilterFactoryFromProtoTyped(
    const FilterConfig& proto_config,
    const std::string& stats_prefix,
    Server::Configuration::FactoryContext& context) {
  
  return [](Http::FilterChainFactoryCallbacks& callbacks) -> void {
    callbacks.addStreamFilter(std::make_shared<Filter>());
  };
}

/**
 * 静的登録
 */
REGISTER_FACTORY(Factory, Server::Configuration::NamedHttpFilterConfigFactory);

} // namespace MyFilter
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
```

#### BUILD ファイル

```python
load(
    "//bazel:envoy_build_system.bzl",
    "envoy_cc_extension",
    "envoy_cc_library",
    "envoy_extension_package",
)

envoy_extension_package()

envoy_cc_library(
    name = "filter_lib",
    srcs = ["filter.cc"],
    hdrs = ["filter.h"],
    deps = [
        "//envoy/http:filter_interface",
        "//source/common/common:logger_lib",
        "//source/extensions/filters/http/common:pass_through_filter_lib",
    ],
)

envoy_cc_extension(
    name = "config",
    srcs = ["config.cc"],
    hdrs = ["config.h"],
    security_posture = "robust_to_untrusted_downstream",
    deps = [
        ":filter_lib",
        "//envoy/server:filter_config_interface",
        "//source/extensions/filters/http/common:factory_base_lib",
    ],
)
```

### 3. 拡張機能の登録

拡張機能をEnvoyに登録するには、以下のファイルを編集します：

1. `source/extensions/extensions_build_config.bzl` - 拡張機能をビルド設定に追加
2. `source/extensions/all_extensions.bzl` - 必要に応じて、コア拡張機能として追加

### 4. 拡張機能のテスト

拡張機能のテストを作成します：

```
test/extensions/filters/http/my_filter/
├── BUILD
├── my_filter_test.cc
└── my_filter_integration_test.cc
```

`my_filter_test.cc`:

```cpp
#include "source/extensions/filters/http/my_filter/filter.h"
#include "test/mocks/http/mocks.h"
#include "test/test_common/utility.h"

#include "gmock/gmock.h"
#include "gtest/gtest.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace MyFilter {

class MyFilterTest : public testing::Test {
public:
  void SetUp() override {
    filter_ = std::make_unique<Filter>();
    filter_->setDecoderFilterCallbacks(decoder_callbacks_);
    filter_->setEncoderFilterCallbacks(encoder_callbacks_);
  }

  std::unique_ptr<Filter> filter_;
  NiceMock<Http::MockStreamDecoderFilterCallbacks> decoder_callbacks_;
  NiceMock<Http::MockStreamEncoderFilterCallbacks> encoder_callbacks_;
};

TEST_F(MyFilterTest, DecodeHeaders) {
  Http::TestRequestHeaderMapImpl headers;
  EXPECT_EQ(Http::FilterHeadersStatus::Continue, filter_->decodeHeaders(headers, true));
}

} // namespace MyFilter
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
```

## WASM拡張機能の開発

WebAssembly（WASM）を使用すると、Envoyのランタイムにロード可能な拡張機能を作成できます。これにより、Envoyのコードベースを変更せずに拡張機能を追加できます。

### 1. 開発環境のセットアップ

WASM拡張機能を開発するには、以下のツールが必要です：

- Bazel
- emscripten（WASMコンパイラ）
- Envoy Proxy WASM SDK

### 2. プロジェクト構造

```
my_wasm_filter/
├── BUILD
├── filter.cc
└── filter.proto
```

### 3. フィルターの実装

`filter.cc`:

```cpp
#include "proxy_wasm_intrinsics.h"

class MyRootContext : public RootContext {
public:
  explicit MyRootContext(uint32_t id, std::string_view root_id) : RootContext(id, root_id) {}

  bool onConfigure(size_t) override;
  bool onStart(size_t) override { return true; }
};

class MyHttpContext : public Context {
public:
  explicit MyHttpContext(uint32_t id, RootContext* root) : Context(id, root) {}

  FilterHeadersStatus onRequestHeaders(uint32_t headers, bool end_of_stream) override;
  FilterDataStatus onRequestBody(size_t body_buffer_length, bool end_of_stream) override;
  FilterHeadersStatus onResponseHeaders(uint32_t headers, bool end_of_stream) override;
  FilterDataStatus onResponseBody(size_t body_buffer_length, bool end_of_stream) override;
};

static RegisterContextFactory register_MyHttpContext(CONTEXT_FACTORY(MyHttpContext),
                                                    ROOT_FACTORY(MyRootContext),
                                                    "my_wasm_filter");

bool MyRootContext::onConfigure(size_t configuration_size) {
  // 設定の処理
  return true;
}

FilterHeadersStatus MyHttpContext::onRequestHeaders(uint32_t headers, bool end_of_stream) {
  // リクエストヘッダーの処理
  addRequestHeader("x-wasm-filter", "hello");
  return FilterHeadersStatus::Continue;
}

FilterDataStatus MyHttpContext::onRequestBody(size_t body_buffer_length, bool end_of_stream) {
  // リクエストボディの処理
  return FilterDataStatus::Continue;
}

FilterHeadersStatus MyHttpContext::onResponseHeaders(uint32_t headers, bool end_of_stream) {
  // レスポンスヘッダーの処理
  addResponseHeader("x-wasm-filter", "hello");
  return FilterHeadersStatus::Continue;
}

FilterDataStatus MyHttpContext::onResponseBody(size_t body_buffer_length, bool end_of_stream) {
  // レスポンスボディの処理
  return FilterDataStatus::Continue;
}
```

### 4. ビルドとデプロイ

WASM拡張機能をビルドするには：

```bash
bazel build //my_wasm_filter:filter.wasm
```

ビルドされたWASMモジュールは、Envoyの設定で使用できます：

```yaml
http_filters:
- name: envoy.filters.http.wasm
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
    config:
      name: "my_wasm_filter"
      root_id: "my_wasm_filter_root"
      vm_config:
        vm_id: "my_wasm_vm"
        runtime: "envoy.wasm.runtime.v8"
        code:
          local:
            filename: "/path/to/filter.wasm"
```

## Lua フィルターを使用した拡張

Envoyは、Luaスクリプトを使用してHTTPフィルターを実装する機能も提供しています。これは、C++やWASMよりも簡単に拡張機能を作成する方法です。

### Lua フィルターの設定例

```yaml
http_filters:
- name: envoy.filters.http.lua
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
    inline_code: |
      function envoy_on_request(request_handle)
        -- リクエストの処理
        request_handle:headers():add("x-lua-filter", "hello")
      end

      function envoy_on_response(response_handle)
        -- レスポンスの処理
        response_handle:headers():add("x-lua-filter", "hello")
      end
```

## ベストプラクティス

### 1. 適切な拡張方法の選択

- **コア拡張機能**: 高性能が必要な場合や、Envoyの内部APIに深くアクセスする必要がある場合
- **WASM拡張機能**: 動的ロード/アンロードが必要な場合や、言語に依存しない拡張機能が必要な場合
- **Lua フィルター**: 簡単な処理や迅速なプロトタイピングが必要な場合

### 2. パフォーマンスの考慮

- コア拡張機能は最高のパフォーマンスを提供します
- WASM拡張機能はある程度のオーバーヘッドがありますが、安全性と柔軟性を提供します
- Luaフィルターは最も簡単ですが、複雑な処理には向いていません

### 3. テストの重要性

- ユニットテストとインテグレーションテストを作成して、拡張機能の動作を検証します
- エッジケースと異常系のテストを含めます
- パフォーマンステストを実施して、拡張機能がEnvoyのパフォーマンスに与える影響を評価します

### 4. ドキュメント

- 拡張機能の目的と使用方法を明確に文書化します
- 設定オプションとその効果を説明します
- 例とチュートリアルを提供します

## まとめ

Envoyは様々な方法で拡張できる柔軟なプロキシです。コア拡張機能、WASM拡張機能、Luaフィルターなど、ユースケースに最適な方法を選択できます。拡張機能を開発する際は、パフォーマンス、保守性、テスト容易性を考慮することが重要です。

詳細については、[Envoyの公式開発者ドキュメント](https://github.com/envoyproxy/envoy/tree/main/DEVELOPER.md)を参照してください。
