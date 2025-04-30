# Envoy Proxy

![Envoy Logo](https://github.com/envoyproxy/artwork/blob/main/PNG/Envoy_Logo_Final_PANTONE.png)

## 概要

Envoyは、クラウドネイティブアプリケーション向けに設計された、オープンソースのエッジおよびサービスプロキシです。元々Lyftで開発され、現在は[Cloud Native Computing Foundation (CNCF)](https://cncf.io)によってホストされています。

このリポジトリは、Envoyプロキシとそのウェブサイトの包括的な理解を提供するドキュメントを含んでいます。

## ドキュメント構成

```
.
├── README.md                    # このファイル
├── docs/                        # 詳細ドキュメント
│   ├── architecture/            # アーキテクチャ関連ドキュメント
│   │   ├── overview.md          # アーキテクチャ概要
│   │   ├── threading_model.md   # スレッディングモデル
│   │   ├── hot_restart.md       # ホットリスタート機能
│   │   └── ...
│   ├── usage/                   # 使用方法関連ドキュメント
│   │   ├── getting_started.md   # 入門ガイド
│   │   ├── configuration.md     # 設定ガイド
│   │   └── ...
│   └── development/             # 開発関連ドキュメント
│       ├── building.md          # ビルド方法
│       ├── extending.md         # 拡張方法
│       └── ...
└── examples/                    # サンプルアプリケーション
    └── kind/                    # Kindで動作するサンプル
```

## 主要なドキュメント

- [アーキテクチャ概要](docs/architecture/overview.md) - Envoyの設計思想と全体アーキテクチャ
- [入門ガイド](docs/usage/getting_started.md) - Envoyを始めるための手順
- [設定ガイド](docs/usage/configuration.md) - Envoyの設定方法の詳細
- [ビルド方法](docs/development/building.md) - Envoyのビルド方法
- [Kindサンプル](examples/kind/README.md) - Kindで動作するサンプルアプリケーション

## ライセンス

Envoyは[Apache License 2.0](https://github.com/envoyproxy/envoy/blob/main/LICENSE)の下で配布されています。
