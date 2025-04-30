# Envoy ビルドガイド

このドキュメントでは、Envoyをソースコードからビルドする方法について説明します。Envoyは[Bazel](https://bazel.build/)ビルドシステムを使用しており、様々なプラットフォームでのビルドをサポートしています。

## 前提条件

Envoyをビルドするには、以下のツールが必要です：

- Git
- Python 3
- C++コンパイラ（GCC 9+またはClang 10+）
- Bazel

## サポートされているプラットフォーム

Envoyは以下のプラットフォームでのビルドをサポートしています：

- Linux (Ubuntu 20.04/22.04, Debian 11/12)
- macOS (10.15+)
- Windows 10/11 (制限付き)

## Dockerを使用したビルド（推奨）

Envoyのビルドに最も簡単で再現性の高い方法は、公式のDockerビルドコンテナを使用することです。

### 1. リポジトリのクローン

```bash
git clone https://github.com/envoyproxy/envoy.git
cd envoy
```

### 2. Dockerを使用したビルド

```bash
# Envoyバイナリをビルド
./ci/run_envoy_docker.sh './ci/do_ci.sh bazel.release'

# ビルド成果物は ./build/envoy/source/exe/envoy-static に生成されます
```

その他のビルドターゲット：

```bash
# デバッグビルド
./ci/run_envoy_docker.sh './ci/do_ci.sh bazel.debug'

# テストの実行
./ci/run_envoy_docker.sh './ci/do_ci.sh bazel.test'

# カバレッジビルド
./ci/run_envoy_docker.sh './ci/do_ci.sh bazel.coverage'

# ドキュメントのビルド
./ci/run_envoy_docker.sh './ci/do_ci.sh docs'
```

## ネイティブビルド（Dockerなし）

### Ubuntu/Debian Linux

#### 1. 依存関係のインストール

```bash
# 必要なパッケージをインストール
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    curl \
    git \
    libtool \
    ninja-build \
    python3 \
    python3-pip \
    unzip

# Bazelのインストール
npm install -g @bazel/bazelisk
```

#### 2. リポジトリのクローン

```bash
git clone https://github.com/envoyproxy/envoy.git
cd envoy
```

#### 3. Envoyのビルド

```bash
bazel build -c opt //source/exe:envoy-static
```

ビルドが完了すると、バイナリは `bazel-bin/source/exe/envoy-static` に生成されます。

### macOS

#### 1. 依存関係のインストール

```bash
# Homebrewをインストール（まだ持っていない場合）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 必要なパッケージをインストール
brew install cmake libtool go bazelisk ninja coreutils automake autoconf

# Xcodeコマンドラインツールをインストール
xcode-select --install
```

#### 2. リポジトリのクローン

```bash
git clone https://github.com/envoyproxy/envoy.git
cd envoy
```

#### 3. Envoyのビルド

```bash
bazel build -c opt //source/exe:envoy-static
```

### Windows

Windows上でのEnvoyのビルドは、WSL2（Windows Subsystem for Linux 2）を使用することを強く推奨します。WSL2内でUbuntu 20.04または22.04をインストールし、上記のLinuxの手順に従ってください。

ネイティブWindowsでのビルドは可能ですが、複雑で制限があります。詳細は[公式ドキュメント](https://github.com/envoyproxy/envoy/tree/main/bazel/EXTERNAL_DEPS.md#windows)を参照してください。

## ビルドオプション

### コンパイラの選択

特定のコンパイラを使用するには：

```bash
# GCCを使用
CC=gcc CXX=g++ bazel build -c opt //source/exe:envoy-static

# Clangを使用
CC=clang CXX=clang++ bazel build -c opt //source/exe:envoy-static
```

### ビルド最適化

ビルド最適化レベルを指定できます：

```bash
# デバッグビルド（最適化なし、デバッグシンボル付き）
bazel build -c dbg //source/exe:envoy-static

# 最適化ビルド
bazel build -c opt //source/exe:envoy-static

# 高度な最適化ビルド
bazel build -c opt --config=release //source/exe:envoy-static
```

### 特定の機能の有効化/無効化

特定の機能を有効または無効にしてビルドできます：

```bash
# 例：HTTPSを無効にしてビルド
bazel build -c opt --define=ssl=disabled //source/exe:envoy-static

# 例：gRPCを無効にしてビルド
bazel build -c opt --define=grpc=disabled //source/exe:envoy-static
```

## テストの実行

### 全テストの実行

```bash
bazel test //test/...
```

### 特定のテストの実行

```bash
# 例：HTTPコネクションマネージャーのテストを実行
bazel test //test/common/http:conn_manager_impl_test

# 例：統合テストを実行
bazel test //test/integration:http2_integration_test
```

### テストフィルタリング

特定のテストケースのみを実行するには：

```bash
bazel test //test/common/http:conn_manager_impl_test --test_filter="ConnectionManagerImplTest.StartAndFinish"
```

## カバレッジレポートの生成

コードカバレッジレポートを生成するには：

```bash
bazel coverage //test/...
```

カバレッジレポートは `bazel-testlogs` ディレクトリに生成されます。

## ドキュメントのビルド

ドキュメントをビルドするには：

```bash
bazel run //docs:html
```

ビルドされたドキュメントは `generated/docs` ディレクトリに生成されます。

## トラブルシューティング

### 一般的な問題

#### 1. メモリ不足エラー

Bazelビルドは大量のメモリを消費します。メモリ不足エラーが発生した場合は、以下のオプションを試してください：

```bash
# Bazelのメモリ使用量を制限
bazel build --local_ram_resources=4096 -c opt //source/exe:envoy-static
```

#### 2. ディスク容量不足

Envoyのビルドには約10GB以上のディスク容量が必要です。ディスク容量不足エラーが発生した場合は、不要なファイルを削除するか、より大きなディスクを使用してください。

#### 3. 依存関係の問題

依存関係の問題が発生した場合は、以下のコマンドでワークスペースをクリーンアップしてみてください：

```bash
bazel clean --expunge
```

#### 4. コンパイラエラー

コンパイラエラーが発生した場合は、サポートされているコンパイラバージョンを使用していることを確認してください。GCC 9+またはClang 10+が推奨されています。

## 高度なトピック

### カスタムビルド設定

`.bazelrc`ファイルを編集することで、デフォルトのビルド設定をカスタマイズできます。

### 拡張機能の追加/削除

特定の拡張機能を含めるまたは除外するには、`bazel/extensions_build_config.bzl`ファイルを編集します。

### サードパーティ依存関係の管理

サードパーティ依存関係は`bazel/repository_locations.bzl`ファイルで管理されています。

## まとめ

このガイドでは、Envoyをソースコードからビルドする方法について説明しました。最も簡単で再現性の高い方法は、公式のDockerビルドコンテナを使用することですが、ネイティブビルドも可能です。

詳細については、[Envoyの公式ビルドドキュメント](https://github.com/envoyproxy/envoy/blob/main/bazel/README.md)を参照してください。
