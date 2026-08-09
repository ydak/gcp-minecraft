#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"
# shellcheck source=const.sh
. "$script_dir/const.sh"

ZONE=us-west1-b
SERVER_NAME=minecraft

echo "==================== Minecraft の設定変更 ===================="

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

[ERROR] サーバーが見つからないか、起動していません。
        (Server '$SERVER_NAME' was not found in zone $ZONE, or it is not running.)

現在のプロジェクトは '$project_id' です。対象が正しいか、
またサーバーが起動しているか確認して下さい。

EOS
  exit 1
fi

# CURRENT SETTINGS ==========
# Taken from the container's environment rather than server.properties: those
# variables are what the next restart will write into the file, so they are the
# values actually in force.
echo -n "  現在の設定を読み込み中 "
env_out=$(mktemp)
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="docker inspect mc-server --format '{{range .Config.Env}}{{println .}}{{end}}'" \
  > "$env_out" 2>/dev/null &
wait_with_dots $! || true

current_of() {
  grep -E "^$1=" "$env_out" 2> /dev/null | head -1 | cut -d= -f2- | tr -d '\r'
}

server_name=$(current_of SERVER_NAME)
game_mode=$(current_of GAMEMODE)
difficulty=$(current_of DIFFICULTY)
allow_cheat=$(current_of ALLOW_CHEATS)
permission=$(current_of DEFAULT_PLAYER_PERMISSION_LEVEL)
max_players=$(current_of MAX_PLAYERS)
view_distance=$(current_of VIEW_DISTANCE)
# The world already exists, so the seed cannot be changed. Carried through
# unaltered so that regenerating the startup script does not drop it.
seed=$(current_of LEVEL_SEED)
rm -f "$env_out"

if [ -z "$server_name" ]; then
  echo " 失敗"
  cat <<EOS

[ERROR] 現在の設定を読み込めませんでした。
        サーバーが起動しているか確認して下さい。

  gcloud compute ssh --quiet $SERVER_NAME --zone=$ZONE --command='docker ps'

EOS
  exit 1
fi
echo " 完了"

# Returns the 1-based position of a value in the remaining arguments, so the
# current setting can be offered as the menu default.
index_of() {
  local needle=$1
  shift
  local i=1
  local v
  for v in "$@"; do
    if [ "$v" == "$needle" ]; then
      echo "$i"
      return
    fi
    i=$((i + 1))
  done
  echo 1
}

cat <<EOS

-*-*-*-*- [現在の設定] -*-*-*-*-
プロジェクト : ${project_id} (${project_num})
サーバー名   : ${server_name}
ゲームモード : ${game_mode}
難易度       : ${difficulty}
チート       : ${allow_cheat}
参加者の権限 : ${permission}
最大人数     : ${max_players}
描画距離     : ${view_distance}

変更したい項目だけ入力してください。
そのまま Enter を押すと現在の値を保ちます。
EOS

# SERVER NAME ==========
cat <<EOS

-*-*-*-*- [SERVER NAME (マインクラフトサーバー名)] -*-*-*-*-
EOS
echo -n "Server name (Default: ${server_name}): "
read -r input
if [ "$input" != "" ]; then server_name=$input ; fi

# GAME MODE ==========
game_mode_default=$(index_of "$game_mode" "${game_mode_list[@]}")
cat <<EOS

-*-*-*-*- [GAME MODE (ゲームモードを選択)] -*-*-*-*-
[1] survival (サバイバル)
[2] creative (クリエイティブ)
[3] adventure (アドベンチャー)
EOS
echo -n "Select game mode (Default: ${game_mode_default}): "
read -r input
if [ "$input" == "" ]; then input=$game_mode_default ; fi
num_validation "$input" 3
game_mode=${game_mode_list[$input-1]}

# DIFFICULTY ==========
difficulty_default=$(index_of "$difficulty" "${difficulty_list[@]}")
cat <<EOS

-*-*-*-*- [DIFFICULTY (難易度を選択)] -*-*-*-*-
[1] peaceful (ピースフル)
[2] easy (イージー)
[3] normal (ノーマル)
[4] hard (ハード)
EOS
echo -n "Difficulty (Default: ${difficulty_default}): "
read -r input
if [ "$input" == "" ]; then input=$difficulty_default ; fi
num_validation "$input" 4
difficulty=${difficulty_list[$input-1]}

# CHEAT ==========
allow_cheat_default=$(index_of "$allow_cheat" "${allow_cheat_list[@]}")
cat <<EOS

-*-*-*-*- [CHEAT (チートを有効にするかどうか)] -*-*-*-*-
[1] ON (有効)
[2] OFF (無効)
EOS
echo -n "Allow cheat? (Default: ${allow_cheat_default}): "
read -r input
if [ "$input" == "" ]; then input=$allow_cheat_default ; fi
num_validation "$input" 2
allow_cheat=${allow_cheat_list[$input-1]}

# PERMISSION ==========
permission_default=$(index_of "$permission" "${permission_num_list[@]}")
cat <<EOS

-*-*-*-*- [PERMISSION (サーバーに参加するユーザー全員の権限)] -*-*-*-*-
[1] visitor (訪問者)
[2] member (メンバー)
[3] operator (管理者)
EOS
echo -n "Default permission (Default: ${permission_default}): "
read -r input
if [ "$input" == "" ]; then input=$permission_default ; fi
num_validation "$input" 3
permission=${permission_num_list[$input-1]}

# MAX PLAYERS ==========
cat <<EOS

-*-*-*-*- [MAX PLAYERS (同時に接続できる最大人数)] -*-*-*-*-
無料枠の e2-micro はメモリが 1GB しかないため、3 人程度が実用上の上限です。
EOS
echo -n "Max players (Default: ${max_players}): "
read -r input
if [ "$input" != "" ]; then
  positive_num_validation "$input"
  max_players=$input
fi
if [ "$max_players" -ge 5 ]; then
  echo "[WARN] $max_players 人はメモリ 1GB に収まらない可能性があります。"
fi

# VIEW DISTANCE ==========
cat <<EOS

-*-*-*-*- [VIEW DISTANCE (描画距離。単位はチャンク)] -*-*-*-*-
大きくすると遠くまで見えますが、通信量とメモリを多く使います。
Minecraft の既定は 32 ですが、無料枠では 10 前後が現実的です。
指定できるのは 5 以上です。
EOS
echo -n "View distance (Default: ${view_distance}): "
read -r input
if [ "$input" != "" ]; then
  positive_num_validation "$input"
  if [ "$input" -lt 5 ]; then
    echo "[ERROR] 5 以上を指定して下さい。"
    exit 1
  fi
  view_distance=$input
fi

cat <<EOS

-*-*-*-*- [変更後の設定] -*-*-*-*-
サーバー名   : ${server_name}
ゲームモード : ${game_mode}
難易度       : ${difficulty}
チート       : ${allow_cheat}
参加者の権限 : ${permission}
最大人数     : ${max_players}
描画距離     : ${view_distance}

この内容で設定を変更します。
反映にはサーバーの再起動が必要なため、接続中のプレイヤーは全員切断されます。
ワールドのデータはそのまま残ります。
EOS

echo -n "よろしいですか? [y/N]: "
read -r config_yn
if [ "$config_yn" != "y" ]; then exit 1 ; fi

echo ""

# The settings live in the startup script held as instance metadata. Rewriting
# server.properties would be undone by the next container start, which rebuilds
# it from these variables.
startup_script=$(mktemp)
trap 'rm -f "$startup_script"' EXIT
render_startup_script "$startup_script"

run_step "設定の書き込み中" \
  gcloud compute instances add-metadata "$SERVER_NAME" --zone="$ZONE" \
  --metadata-from-file=startup-script="$startup_script"

echo -n "  再起動中 "

# Rebooting re-runs the startup script, which recreates the container with the
# new values. The connection drops as the instance goes down, so ssh reports
# failure here; wait_for_server below is what confirms the outcome.
gcloud compute ssh --quiet --zone "$ZONE" "$SERVER_NAME" \
  --command="docker stop -t 60 mc-server && sudo reboot" > /dev/null 2>&1 &
wait_with_dots $! || true

echo " 完了"
echo ""
echo -n "マインクラフト再起動中 "

if wait_for_server "$external_ip" 900; then
  cat <<EOS

設定の変更が完了しました！

################################################################################
${external_ip}
################################################################################

EOS
else
  cat <<EOS

[WARN] 15 分待ちましたが、サーバーが応答しませんでした。

設定は書き込まれています。起動に時間がかかっているだけかもしれません。
下記でログを確認できます。

  gcloud compute ssh --quiet $SERVER_NAME --zone=$ZONE --command='docker logs mc-server | tail -30'

EOS
  exit 1
fi
