#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"

ZONE=us-west1-b
SERVER_NAME=minecraft

echo "==================== Minecraft の更新 ===================="

# GOOGLE CLOUD ==========
echo -n "確認しています ... "
project_id=$(gcloud config get project)
project_num=$(gcloud projects describe "$project_id" --format="value(projectNumber)")
gcloud config set project "$project_id" > /dev/null
echo "完了"

# A stopped instance has no external IP, so an empty value is also a failure.
external_ip=$(gcloud compute instances describe "$SERVER_NAME" --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)

if [ -z "$external_ip" ]; then
  cat <<EOS

[ERROR] Server '$SERVER_NAME' was not found in zone $ZONE, or it is not running.
        (ゾーン $ZONE にサーバーが無いか、起動していません。)

The current project is '$project_id'. Check that it is the right one,
and that the server is running.
(現在のプロジェクトは '$project_id' です。対象が正しいか、
 またサーバーが起動しているか確認して下さい。)

  gcloud compute instances list

EOS
  exit 1
fi

cat <<EOS

-*-*-*-*- [更新対象の確認] -*-*-*-*-
プロジェクト ID
　$project_id
プロジェクト番号
　$project_num
サーバー名
　$SERVER_NAME
IP アドレス
　$external_ip

上記のマインクラフトを最新バージョンに更新します。
更新中はサーバーが停止するため、接続中のプレイヤーは全員切断されます。
EOS

echo -n "よろしいですか? [y/N]: "
read -r update_yn
if [ "$update_yn" != "y" ]; then exit 1 ; fi

# Rebooting is the update mechanism for the whole stack, not just a way to
# apply an OS update:
#
#   - Container-Optimized OS swaps to whatever it staged on its spare partition
#   - the startup script pulls the wrapper image again and recreates the
#     container, so its base libraries do not age
#   - the container fetches the current Bedrock binary as it starts
#
# `docker restart` alone would only cover the last of those three, so this
# always reboots rather than picking the cheaper path.
#
# Note that the first two only apply to instances created by a create.sh that
# writes this startup script. On older instances the reboot still refreshes
# Bedrock, and nothing breaks.
os_status=$(gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" \
  --command="sudo update_engine_client --status 2>/dev/null | grep CURRENT_OP" 2>/dev/null || true)

if echo "$os_status" | grep -q "UPDATED_NEED_REBOOT"; then
  echo "OS の更新が見つかりました。あわせて適用します。"
else
  echo "OS の更新はありません。"
fi

echo -n "  更新しています ... "

# The image turns SIGTERM into a clean `stop`, but the shutdown sequence is
# less forgiving than `docker stop`, so stop the container explicitly first.
# The connection drops as the instance goes down, so ssh reports failure here;
# wait_for_server below is what actually confirms the outcome.
gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" \
  --command="docker stop -t 60 mc-server && sudo reboot" > /dev/null 2>&1 || true

echo "完了"
echo ""
echo -n "マインクラフトの再起動を待っています "

if wait_for_server "$external_ip" 900; then
  cat <<EOS

更新が完了しました！

################################################################################
${external_ip}
################################################################################

EOS
else
  cat <<EOS

[WARN] 15 分待ちましたが、サーバーが応答しませんでした。

新しいバージョンを取得している途中かもしれません。
下記でログを確認できます。

  gcloud compute ssh $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi

