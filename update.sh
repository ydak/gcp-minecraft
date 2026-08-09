#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"

ZONE=us-west1-b
SERVER_NAME=minecraft

echo ""
echo "==================== Minecraft の更新 ===================="
echo ""

# GOOGLE CLOUD ==========
# Run in the background so the dots reflect real elapsed time rather than
# being three characters printed up front.
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
# The first `gcloud compute ssh` in a fresh CloudShell generates an SSH key,
# which takes long enough to look like a hang with no output at all.
echo -n "  サーバーへ接続中 "
os_out=$(mktemp)
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="sudo update_engine_client --status 2>/dev/null | grep CURRENT_OP" \
  > "$os_out" 2>/dev/null &
wait_with_dots $! || true
os_status=$(cat "$os_out" 2>/dev/null || true)
rm -f "$os_out"
echo " 完了"

if echo "$os_status" | grep -q "UPDATED_NEED_REBOOT"; then
  echo "OS の更新が見つかりました。あわせて適用します。"
else
  echo "OS の更新はありません。"
fi

echo -n "  更新中 "

# The image turns SIGTERM into a clean `stop`, but the shutdown sequence is
# less forgiving than `docker stop`, so stop the container explicitly first.
# The connection drops as the instance goes down, so ssh reports failure here;
# wait_for_server below is what actually confirms the outcome.
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="docker stop -t 60 mc-server && sudo reboot" > /dev/null 2>&1 &
wait_with_dots $! || true

echo " 完了"
echo ""
echo -n "マインクラフト再起動中 "

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

  gcloud compute ssh --quiet $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi

