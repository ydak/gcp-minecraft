#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"
# shellcheck source=const.sh
. "$script_dir/const.sh"

echo "==================== Minecraft サーバーの削除 ===================="

# GOOGLE CLOUD ==========
# Run in the background so the dots reflect real elapsed time rather than being
# three characters printed up front.
# Declared up front: they are assigned by sourcing the file the subshell
# writes, which neither shellcheck nor set -e can see into.
project_id=""
project_num=""
echo -n "確認中 "
gcloud_info=$(mktemp)
(
  pid=$(gcloud config get project 2> /dev/null)
  pnum=$(gcloud projects describe "$pid" --format="value(projectNumber)" 2> /dev/null)
  gcloud config set project "$pid" > /dev/null 2>&1
  printf 'project_id=%q\nproject_num=%q\n' "$pid" "$pnum"
) > "$gcloud_info" 2> /dev/null &
wait_with_dots $! || true
# shellcheck disable=SC1090
. "$gcloud_info"
rm -f "$gcloud_info"
if [ -z "$project_id" ]; then
  echo " 失敗"
  cat <<EOS

[ERROR] Google Cloud のプロジェクトを取得できませんでした。
        下記で対象を指定してから、もう一度お試しください。

  gcloud config set project <プロジェクト ID>

EOS
  exit 1
fi
echo " 完了"

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

