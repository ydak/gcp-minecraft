#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"

ZONE=us-west1-b
SERVER_NAME=minecraft
BACKUP_DIR="$HOME"

echo "==================== ワールドのバックアップ ===================="

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

The current project is '$project_id'. Check that it is the right one.
(現在のプロジェクトは '$project_id' です。対象が正しいか確認して下さい。)

EOS
  exit 1
fi

# The first `gcloud compute ssh` in a fresh CloudShell generates an SSH key.
# Without --quiet it stops on a confirmation prompt, and with stderr discarded
# that prompt is invisible, so the script looks like it has hung. --quiet
# answers it, and the dots show that something is still happening: key
# generation and the first connection together take the best part of a minute.
echo -n "  サーバーへ接続中 "
size_out=$(mktemp)
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="docker run --rm -v mc-volume:/data busybox du -sh /data/worlds 2>/dev/null | cut -f1" \
  > "$size_out" 2>/dev/null &
wait_with_dots $! || true
world_size=$(cat "$size_out" 2>/dev/null || true)
rm -f "$size_out"
echo " 完了"

cat <<EOS

-*-*-*-*- [バックアップ対象の確認] -*-*-*-*-
プロジェクト ID
　$project_id
プロジェクト番号
　$project_num
サーバー名
　$SERVER_NAME
ワールドのサイズ
　${world_size:-(取得できませんでした)}
保存先
　$BACKUP_DIR

ワールドデータをバックアップします。
書き込み途中のデータを掴まないよう、いったんサーバーを停止します。
接続中のプレイヤーは全員切断されます。
EOS

echo -n "よろしいですか? [y/N]: "
read -r backup_yn
if [ "$backup_yn" != "y" ]; then exit 1 ; fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_file="${BACKUP_DIR}/minecraft-backup-${timestamp}.tar.gz"

# Stop the server before reading the world. The Bedrock world is a LevelDB
# directory, so archiving it mid-write can produce a backup that does not
# restore. The image turns SIGTERM into a clean `stop`.
echo ""
run_step "サーバーの停止中" \
  gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" --command="docker stop -t 60 mc-server"

echo -n "  ワールドの取得中 "

# busybox is a couple of megabytes and is guaranteed to carry tar and sh, so it
# is used rather than reaching into the volume's host path, which would need
# sudo. The archive is streamed straight to CloudShell: no temporary file is
# written on the instance, whose /tmp is RAM backed and whose disk is only 10GB.
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="docker run --rm -v mc-volume:/data busybox tar cz -C /data worlds" \
  > "$backup_file" 2>/dev/null &

download_status=0
wait_with_dots $! || download_status=$?

if [ "$download_status" -ne 0 ]; then
  rm -f "$backup_file"
  echo " 失敗"
  echo "[ERROR] ワールドを取得できませんでした。"
  gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" --command="docker start mc-server" > /dev/null 2>&1 || true
  exit 1
fi

echo " 完了"
run_step "サーバーの再開中" \
  gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" --command="docker start mc-server"

# Reading the archive back decompresses every entry and checks the gzip CRC, so
# this catches a truncated or corrupted transfer before it is trusted.
echo -n "  データの検証中 "
tar tzf "$backup_file" > /dev/null 2>&1 &
verify_status=0
wait_with_dots $! || verify_status=$?

if [ "$verify_status" -ne 0 ]; then
  rm -f "$backup_file"
  echo " 失敗"
  echo "[ERROR] データが壊れていたため破棄しました。"
  exit 1
fi
echo " 完了"

backup_size=$(du -h "$backup_file" | cut -f1)

# The archive only lives in CloudShell's home directory, which is itself
# ephemeral, so hand it to the browser rather than leaving the user to find it
# in the editor. `cloudshell download` asks the browser to start the download.
# It is missing outside CloudShell, and a refused download should not fail the
# backup, so neither case is treated as an error.
if command -v cloudshell > /dev/null; then
  echo "ブラウザにダウンロードの確認が表示されます。"
  cloudshell download "$backup_file" || true
  download_started=1
else
  download_started=0
fi

echo ""
echo -n "マインクラフト再開中 "

if wait_for_server "$external_ip" 900; then
  cat <<EOS

バックアップが完了しました！

################################################################################
${backup_file}
${backup_size}
################################################################################

復元するときは restore を選んで下さい。
(Choose restore to put this world back.)

EOS

  if [ "$download_started" == "1" ]; then
    cat <<EOS
ブラウザでのダウンロードを開始しました。
確認が出ていない場合は、下記でやり直せます。
(The download has been handed to the browser. Run this again if nothing appeared.)

  cloudshell download ${backup_file}

EOS
  else
    cat <<EOS
CloudShell 以外で実行しているため、自動ダウンロードは行いません。
(Not running in CloudShell, so the download was not started.)

EOS
  fi
else
  cat <<EOS

[WARN] The backup was saved, but the server did not answer within 15 minutes.
       (バックアップは保存できましたが、サーバーが 15 分以内に応答しませんでした。)

################################################################################
${backup_file}
${backup_size}
################################################################################

Check the log with the following command.
(下記でログを確認して下さい。)

  gcloud compute ssh --quiet $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi

