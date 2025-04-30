#!/bin/bash

# Envoy Proxy サンプルアプリケーション クリーンアップスクリプト
# このスクリプトは、Kindクラスター上のEnvoyサンプルアプリケーションをクリーンアップします

set -e

# 色の定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ディレクトリの確認
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${GREEN}Envoy Proxy サンプルアプリケーション クリーンアップを開始します...${NC}"

# Kindクラスターの確認
if ! kind get clusters | grep -q "envoy-demo"; then
  echo -e "${YELLOW}Kindクラスター 'envoy-demo' が見つかりません。クリーンアップは不要です。${NC}"
  exit 0
else
  echo -e "${GREEN}Kindクラスター 'envoy-demo' が見つかりました。クリーンアップを続行します...${NC}"
fi

# kubectlの確認
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}kubectl が見つかりません。インストールしてください。${NC}"
  exit 1
fi

# 名前空間の削除
echo -e "${GREEN}名前空間 'envoy-demo' を削除しています...${NC}"
kubectl delete namespace envoy-demo --ignore-not-found=true

# 確認
echo -e "${GREEN}名前空間が削除されました。${NC}"

# ユーザーに選択肢を提示
echo -e "${YELLOW}Kindクラスター 'envoy-demo' も削除しますか？ (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo -e "${GREEN}Kindクラスター 'envoy-demo' を削除しています...${NC}"
  kind delete cluster --name envoy-demo
  echo -e "${GREEN}Kindクラスターが削除されました。${NC}"
else
  echo -e "${GREEN}Kindクラスターは保持されます。${NC}"
fi

# 生成されたファイルの削除
echo -e "${YELLOW}生成されたマニフェストファイルとConfigファイルを削除しますか？ (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo -e "${GREEN}生成されたファイルを削除しています...${NC}"
  rm -rf manifests configs services
  echo -e "${GREEN}ファイルが削除されました。${NC}"
else
  echo -e "${GREEN}生成されたファイルは保持されます。${NC}"
fi

echo -e "${GREEN}クリーンアップが完了しました！${NC}"
