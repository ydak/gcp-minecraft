#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"
# shellcheck source=const.sh
. "$script_dir/const.sh"

echo "==================== Minecraft サーバーの削除 ===================="

# GOOGLE CLOUD ==========
echo -n "確認中 ... "
project_id=$(gcloud config get project)
project_num=$(gcloud projects list --filter="$project_id" --format="value(PROJECT_NUMBER)")
gcloud config set project "$project_id" > /dev/null
echo "完了"

SERVER_NAME=minecraft
FIREWALL_RULE_NAME=minecraft

cat <<EOS

-*-*-*-*- [削除対象の確認] -*-*-*-*-
プロジェクト ID
　$project_id
プロジェクト番号
　$project_num
サーバー名
　$SERVER_NAME

上記を削除します。
EOS

echo -n "よろしいですか? [y/N]: "
read -r delete_yn
if [ "$delete_yn" != "y" ]; then exit 1 ; fi

echo ""
run_step "サーバーの削除中" \
  gcloud compute instances delete "$SERVER_NAME" --zone=us-west1-b --quiet
run_step "ネットワーク設定の削除中" \
  gcloud compute firewall-rules delete "$FIREWALL_RULE_NAME" --quiet

echo ""
echo "削除が完了しました。"

