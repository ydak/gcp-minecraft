#!/usr/bin/env bash
set -e

script_dir=$(dirname ${0})
. $script_dir/functions.sh
. $script_dir/const.sh

echo "==================== Start delete minecraft server  ===================="

# GOOGLE CLOUD ==========
echo -n "Setting Google Cloud info ..."
project_id=$(gcloud config get project)
project_num=$(gcloud projects list --filter="$project_id" --format="value(PROJECT_NUMBER)")
gcloud config set project $project_id

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

echo "Deleting minecraft server ..."

gcloud compute instances delete $SERVER_NAME --zone=us-west1-b --quiet
gcloud compute firewall-rules delete $FIREWALL_RULE_NAME --quiet

echo "Delete complete!"

echo "==================== End delete minecraft server  ===================="
