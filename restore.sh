#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"

ZONE=us-west1-b
SERVER_NAME=minecraft
BACKUP_DIR="$HOME"

echo "==================== Start minecraft restore ===================="

# GOOGLE CLOUD ==========
echo -n "Setting Google Cloud info ..."
project_id=$(gcloud config get project)
project_num=$(gcloud projects describe "$project_id" --format="value(projectNumber)")
gcloud config set project "$project_id"

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

# BACKUP ==========
# Globbing into an array rather than parsing ls, then reversing so the newest
# backup is offered first.
shopt -s nullglob
backups=("$BACKUP_DIR"/minecraft-backup-*.tar.gz)
shopt -u nullglob

if [ ${#backups[@]} -eq 0 ]; then
  cat <<EOS

[ERROR] No backup was found in $BACKUP_DIR.
        ($BACKUP_DIR にバックアップが見つかりませんでした。)

先に backup を実行するか、手元のファイルをアップロードして下さい。
(Take one with backup first, or upload one from your machine.)

手元のファイルを使う場合:
(To use a file from your machine:)

  1. CloudShell 右上の [ ⋮ ] から Upload を選ぶ
     (Click the [ more_vert ] menu in CloudShell and choose Upload)
  2. ホームディレクトリにアップロードする
     (Upload it to your home directory)
  3. 名前を minecraft-backup-*.tar.gz に合わせる
     (Name it minecraft-backup-*.tar.gz)

手元の PC のターミナルからでも送れます。
(It can also be pushed from a terminal on your machine.)

  gcloud cloud-shell scp localhost:~/minecraft-backup-YYYYmmdd-HHMMSS.tar.gz cloudshell:~/

EOS
  exit 1
fi

mapfile -t backups < <(printf '%s\n' "${backups[@]}" | sort -r)

cat <<EOS

-*-*-*-*- [BACKUP (復元するバックアップを選択)] -*-*-*-*-
EOS
i=1
for b in "${backups[@]}"; do
  echo "[$i] $(basename "$b") ($(du -h "$b" | cut -f1))"
  i=$((i + 1))
done

cat <<EOS

手元のファイルを使う場合は、CloudShell 右上の [ ⋮ ] から Upload で
ホームディレクトリへ置き、minecraft-backup-*.tar.gz という名前にして下さい。
(To use a file from your machine, upload it to your home directory via the
 [ more_vert ] menu and name it minecraft-backup-*.tar.gz.)
EOS

echo -n "Select backup (Default: 1): "
read -r backup_num
if [ "$backup_num" == "" ]; then backup_num=1 ; fi
positive_num_validation "$backup_num"
if [ "$backup_num" -gt "${#backups[@]}" ]; then
  echo "[ERROR] Enter a number from the list. (一覧にある番号を入力して下さい。)"
  exit 1
fi
backup_file="${backups[$backup_num - 1]}"

# Check the archive here rather than after the world has been replaced.
echo "Verifying the archive ..."
if ! tar tzf "$backup_file" > /dev/null 2>&1; then
  echo "[ERROR] $(basename "$backup_file") is corrupted."
  echo "        ($(basename "$backup_file") は壊れています。)"
  exit 1
fi

cat <<EOS

-*-*-*-*- [復元対象の確認] -*-*-*-*-
プロジェクト ID
　$project_id
プロジェクト番号
　$project_num
サーバー名
　$SERVER_NAME
復元するファイル
　$(basename "$backup_file")

現在のワールドを、このバックアップの内容で置き換えます。
今のワールドは worlds.previous として 1 世代だけ残ります。
サーバーは一度停止し、接続中のプレイヤーは全員切断されます。
EOS

echo -n "よろしいですか? [y/N]: "
read -r restore_yn
if [ "$restore_yn" != "y" ]; then exit 1 ; fi

echo "Stopping the server ..."
gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" --command="docker stop -t 60 mc-server" > /dev/null

echo "Uploading the world ..."

# The archive is expanded into a scratch directory first and the current world
# is only moved aside once that has succeeded. A truncated upload therefore
# fails at tar, before anything has been destroyed. The previous world is kept
# as worlds.previous so a restore of the wrong file can still be undone.
restore_cmd='docker run --rm -i -v mc-volume:/data busybox sh -c "
set -e
rm -rf /data/.restore
mkdir -p /data/.restore
tar xz -C /data/.restore
test -d /data/.restore/worlds
rm -rf /data/worlds.previous
if [ -d /data/worlds ]; then mv /data/worlds /data/worlds.previous; fi
mv /data/.restore/worlds /data/worlds
rm -rf /data/.restore
"'

if ! gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" --command="$restore_cmd" \
  < "$backup_file" > /dev/null 2>&1; then
  cat <<EOS

[ERROR] Failed to restore the world. (ワールドの復元に失敗しました。)

The current world was left untouched, since it is only moved aside after the
archive has been expanded successfully.
(アーカイブの展開に成功してから入れ替える作りのため、現在のワールドは
 変更されていません。)

EOS
  gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" --command="docker start mc-server" > /dev/null || true
  exit 1
fi

echo "Restarting the server ..."
gcloud compute ssh --zone "$ZONE" "$SERVER_NAME" --command="docker start mc-server" > /dev/null

echo ""
echo "Waiting for the Minecraft server to come back ..."
echo -n "(マインクラフトサーバーの再起動を待っています) "

if wait_for_server "$external_ip" 900; then
  cat <<EOS

Restore complete!
 (復元が完了しました！)

################################################################################
${external_ip}
################################################################################

置き換える前のワールドは worlds.previous として残っています。
(The world from before this restore is kept as worlds.previous.)

EOS
else
  cat <<EOS

[WARN] The server did not answer within 15 minutes.
       (15分以内にサーバーが応答しませんでした。)

Check the log with the following command.
(下記でログを確認して下さい。)

  gcloud compute ssh $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi

echo "==================== End minecraft restore ===================="
