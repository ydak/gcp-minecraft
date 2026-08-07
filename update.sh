#!/usr/bin/env bash
set -e

script_dir=$(dirname ${0})
. $script_dir/functions.sh

ZONE=us-west1-b
SERVER_NAME=minecraft

echo "==================== Start minecraft update ===================="

# GOOGLE CLOUD ==========
echo -n "Setting Google Cloud info ..."
project_id=$(gcloud config get project)
project_num=$(gcloud projects describe "$project_id" --format="value(projectNumber)")
gcloud config set project $project_id

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

echo "Updating minecraft ..."

# NOTE: The Bedrock server binary is not bundled in the image. It is downloaded
#       from Mojang at container startup, and VERSION defaults to LATEST, so
#       restarting the container is what actually performs the upgrade.
#
#       `docker pull` is deliberately not used here. A running container stays
#       bound to the image it was created from, so pulling a newer image has no
#       effect on it and only piles up unused layers on the 10GB boot disk.
#
#       The image handles SIGTERM by sending `stop` to the server, so the world
#       is saved cleanly before the restart.
gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" --command="docker restart mc-server"

echo ""
echo "Waiting for the Minecraft server to come back ..."
echo -n "(マインクラフトサーバーの再起動を待っています) "

if wait_for_server "$external_ip" 900; then
  cat <<EOS

Minecraft has been updated!
 (マインクラフトの更新が完了しました！)

################################################################################
${external_ip}
################################################################################

EOS
else
  cat <<EOS

[WARN] The server did not answer within 15 minutes.
       (15分以内にサーバーが応答しませんでした。)

The container may still be downloading the new version.
Check the log with the following command.
(新しいバージョンを取得中の可能性があります。下記でログを確認して下さい。)

  gcloud compute ssh $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi

echo "==================== End minecraft update ===================="
