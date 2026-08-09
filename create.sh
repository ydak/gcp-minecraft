#!/usr/bin/env bash
set -e

script_dir=$(dirname "${0}")
# shellcheck source=functions.sh
. "$script_dir/functions.sh"
# shellcheck source=const.sh
. "$script_dir/const.sh"

echo "==================== Minecraft サーバーの作成 ===================="

# GOOGLE CLOUD ==========
# Run in the background so the dots reflect real elapsed time rather than being
# three characters printed up front.
#
# NOTE: `gcloud projects list --filter="$project_id"` is a bare-word filter that
#       matches ANY field. A similarly named project makes it return multiple
#       lines, which silently corrupts the service account name below, so
#       describe is used instead.
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

cat <<EOS

-*-*-*-*- [GOOGLE CLOUD (Google Cloud の情報確認)] -*-*-*-*-
プロジェクト ID  : $project_id
プロジェクト番号 : $project_num

上記の Google Cloud 環境でマインクラフトサーバーを作成します。

・今回作成する Minecraft サーバーの無料枠は、 1 Google Cloud アカウントにつき 1 台までです。
・すでに起動中のサーバーが別にある場合、2 台目は無料枠の対象外となり、
　VM と外部 IP を合わせておおよそ毎月 10 ドル (1,500 円ほど) かかります。
・以前のサーバーを削除済みであれば料金はかかりません。停止中の場合も
　稼働時間は消費しません。無料枠は台数ではなく稼働時間で計算されるためです。
EOS

echo -n "よろしいですか? [y/N]: "
read -r gcp_info
if [ "$gcp_info" != "y" ]; then exit 1 ; fi

# EXISTING SERVER ==========
# Checked before any of the questions below. Creating a second instance fails at
# the very end otherwise, after every setting has been typed in, and the free
# tier only covers one instance anyway.
existing=$(gcloud compute instances describe minecraft --zone=us-west1-b \
  --format="value(status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)

if [ -n "$existing" ]; then
  existing_status=$(echo "$existing" | cut -f1)
  existing_ip=$(echo "$existing" | cut -f2)

  case "$existing_status" in
    RUNNING) existing_status="起動中" ;;
    TERMINATED | STOPPED) existing_status="停止中" ;;
  esac

  cat <<EOS

[ERROR] すでにマインクラフトサーバーが存在します。
        (A Minecraft server already exists in this project.)

 プロジェクト : $project_id
 状態         : $existing_status
 IP アドレス  : ${existing_ip:-(停止中のため割り当てなし)}

無料枠で動かせるサーバーは 1 台までのため、作成を中止しました。

 遊ぶ       : 上記の IP アドレスとポート 19132 で接続してください
 更新する   : メニューから update を選んでください
 作り直す   : メニューから delete を選んでから、もう一度 create してください

作り直すとワールドのデータも消えます。残したい場合は、先にメニューから
backup を実行してください。

EOS
  exit 1
fi

# SERVER NAME ==========
cat <<EOS

-*-*-*-*- [SERVER NAME (マインクラフトサーバー名を自由に決めて下さい)] -*-*-*-*-
EOS
echo -n "Server name (Default: ydak): "
read -r server_name

# GAME MODE ==========
cat <<EOS

-*-*-*-*- [GAME MODE (ゲームモードを選択)] -*-*-*-*-
[1] survival (サバイバル)
[2] creative (クリエイティブ)
[3] adventure (アドベンチャー)
EOS
echo -n "Select game mode (Default: 1): "
read -r game_mode_num
if [ "$game_mode_num" == "" ]; then game_mode_num=1 ; fi
num_validation "$game_mode_num" 3
game_mode=${game_mode_list[$game_mode_num-1]}

# DIFFICULTY ==========
cat <<EOS

-*-*-*-*- [DIFFICULTY (難易度を選択)] -*-*-*-*-
[1] peaceful (ピースフル)
[2] easy (イージー)
[3] normal (ノーマル)
[4] hard (ハード)
EOS
echo -n "Difficulty (Default: 3): "
read -r difficulty_num
if [ "$difficulty_num" == "" ]; then difficulty_num=3 ; fi
num_validation "$difficulty_num" 4
difficulty=${difficulty_list[$difficulty_num-1]}

# CHEAT ==========
cat <<EOS

-*-*-*-*- [CHEAT (チートを有効にするかどうか)] -*-*-*-*-
[1] ON (有効)
[2] OFF (無効)
EOS
echo -n "Allow cheat? (Default: 2): "
read -r allow_cheat_num
if [ "$allow_cheat_num" == "" ]; then allow_cheat_num=2 ; fi
num_validation "$allow_cheat_num" 2
allow_cheat=${allow_cheat_list[$allow_cheat_num-1]}

# PERMISSION ==========
cat <<EOS

-*-*-*-*- [PERMISSION (サーバーに参加するユーザー全員の権限)] -*-*-*-*-
[1] visitor (訪問者)
[2] member (メンバー)
[3] operator (管理者)
EOS
echo -n "Default permission (Default: 2): "
read -r permission_num
if [ "$permission_num" == "" ]; then permission_num=2 ; fi
num_validation "$permission_num" 3
permission=${permission_num_list[$permission_num-1]}

# MAX PLAYERS ==========
cat <<EOS

-*-*-*-*- [MAX PLAYERS (同時に接続できる最大人数)] -*-*-*-*-
無料枠の e2-micro はメモリが 1GB しかないため、3 人程度が実用上の上限です。
それ以上で遊ぶ場合はマシンタイプの変更を検討して下さい。
(The free tier e2-micro has only 1GB of memory, so around 3 players is the
 practical limit. Consider a larger machine type if you need more.)
EOS
echo -n "Max players (Default: 2): "
read -r max_players
if [ "$max_players" == "" ]; then max_players=2 ; fi
positive_num_validation "$max_players"
if [ "$max_players" -ge 5 ]; then
  echo "[WARN] $max_players players may not fit in 1GB of memory."
  echo "       ($max_players 人はメモリ 1GB に収まらない可能性があります。)"
fi

# SEED ==========
cat <<EOS

-*-*-*-*- [SEED (シード値を入力。入力しない場合はランダム)] -*-*-*-*-
EOS
echo -n "Seed (Default: random): "
read -r seed
if [ "$seed" != "" ]; then
  if [[ ! ("$seed" =~ ^[-0-9][0-9]+$) ]]; then
    echo "[ERROR] Enter correct number for seed."
    exit 1
  fi
fi

cat <<EOS

設定が完了しました。サーバーを作成します。数分かかります。
(Configuration is complete. Creating the server. This takes a few minutes.)

EOS

# NOTE: enabling an API counts against the serviceusage "Mutate requests per
#       minute" quota. Hitting it fails the whole script under `set -e`, so
#       retry with a wait longer than the one-minute quota window.
#       A missing billing account is a precondition failure, not a rate limit,
#       so retrying never clears it. Bail out immediately in that case.
#       The output is captured rather than shown: it is a progress spinner and
#       an operation id, neither of which is worth reading unless it fails.
enable_log=$(mktemp)
echo -n "  Google Cloud の準備中 "
for i in 1 2 3 4 5; do
  gcloud services enable compute.googleapis.com > "$enable_log" 2>&1 &
  enable_status=0
  wait_with_dots $! || enable_status=$?
  if [ "$enable_status" -eq 0 ]; then break; fi

  if [ "${MC_VERBOSE:-0}" == "1" ]; then cat "$enable_log"; fi

  if grep -qE 'billing-enabled|UREQ_PROJECT_BILLING_NOT_FOUND|Billing account for project' "$enable_log"; then
    rm -f "$enable_log"
    echo " 失敗"
    cat <<EOS

[ERROR] Billing is not enabled for this project.
        (このプロジェクトに請求先アカウントがリンクされていません。)

A billing account must be linked even when you stay within the Always Free
tier. Linking alone does not incur any charges.
(無料枠の範囲で使う場合でもリンクは必須です。リンクしただけでは課金されません。)

Link a billing account at the following URL, then run this script again.
(下記から請求先アカウントをリンクし、再度このスクリプトを実行して下さい。)

  https://console.cloud.google.com/billing/linkedaccount?project=$project_id

EOS
    exit 1
  fi

  sleep_with_dots 70
done
rm -f "$enable_log"

if ! gcloud services list --enabled \
  --filter="config.name=compute.googleapis.com" \
  --format="value(config.name)" | grep -q .; then
  echo " 失敗"
  cat <<EOS

[ERROR] Google Cloud の準備に失敗しました。
        数分おいて、もう一度お試しください。
        (Failed to enable compute.googleapis.com.)

EOS
  exit 1
fi

# The default compute service account is created when the API is enabled.
# Creating an instance before it exists fails, so wait for it to show up.
for i in $(seq 1 20); do
  if gcloud iam service-accounts describe \
    "$project_num-compute@developer.gserviceaccount.com" >/dev/null 2>&1; then
    break
  fi
  sleep_with_dots 15
done
echo " 完了"

# firewall =====================================================================
fw_minecraft=$(gcloud compute firewall-rules list --format="json" | jq -r '.[] | select(.name=="minecraft")')

if [ -z "$fw_minecraft" ]; then
  run_step "ネットワークの設定中" \
    gcloud compute --project="$project_id" \
    firewall-rules create minecraft \
    --description=minecraft \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:19132,udp:19132 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=minecraft
fi

# GCE ==========================================================================
# NOTE: `test("cos-stable")` is a substring regex over every public image
#       family, so it returns multiple lines the moment another family
#       containing that string appears. describe-from-family is exact.
image=$(gcloud compute images describe-from-family cos-stable \
  --project=cos-cloud --format="value(selfLink)" | sed -E 's|.*/compute/v1/||')

if [ -z "$image" ]; then
  cat <<EOS

[ERROR] サーバーの土台となるイメージを取得できませんでした。
        数分おいて、もう一度お試しください。
        (Failed to resolve the latest COS image.)

EOS
  exit 1
fi

# The startup script moved out of --metadata and into --metadata-from-file.
# --metadata takes comma separated key=value pairs, so a single comma anywhere
# in the script would silently split it into bogus keys. Keeping it in its own
# file leaves --metadata free for cos-update-strategy.
startup_script=$(mktemp)
trap 'rm -f "$startup_script"' EXIT

# VIEW_DISTANCE is set to 5 against a default of 32. Chunk data is the bulk of
# what the server sends and it grows with the square of the radius, so this is
# the largest single lever on outbound traffic, and the default reaches much
# further than a 1GB RAM shared-core instance can comfortably serve in memory,
# CPU and traffic alike. Clients still render past this:
# client-side-chunk-generation is on by default, so distant terrain is
# generated locally rather than sent. Raise it from config when the view
# matters more than the allowance.
#
# This runs on every boot, so it is written to be idempotent and to refresh
# what it can. A reboot is the single update mechanism for the whole stack:
#   - Container-Optimized OS applies whatever it staged onto its spare partition
#   - the wrapper image is pulled again here
#   - the Bedrock binary is fetched when the container starts (VERSION=LATEST)
# update.sh reboots the instance, which is what drives all three.
render_startup_script "$startup_script"

# gcloud writes the created resource URL and any warnings to stderr. Capture it
# so the run stays readable, and print it only if the creation actually failed.
# Splitting the call from the jq parse also means a gcloud failure is caught
# here rather than being masked by jq's exit status.
create_log=$(mktemp)
create_out=$(mktemp)
echo -n "  サーバーの作成中 "

gcloud compute instances create minecraft \
  --format="json" \
  --project="$project_id" \
  --zone=us-west1-b \
  --machine-type=e2-micro \
  --network-interface=network-tier=PREMIUM,subnet=default \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --service-account="$project_num-compute@developer.gserviceaccount.com" \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
  --tags=minecraft \
  --create-disk="auto-delete=yes,boot=yes,device-name=minecraft,image=$image,mode=rw,size=10,type=projects/$project_id/zones/us-west1-b/diskTypes/pd-standard" --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
  --reservation-affinity=any \
  --metadata=cos-update-strategy=update_enabled \
  --metadata-from-file=startup-script="$startup_script" \
  > "$create_out" 2> "$create_log" &

create_status=0
wait_with_dots $! || create_status=$?

if [ "$create_status" -ne 0 ]; then
  echo " 失敗"
  echo ""
  echo "--------------------------------------------------------------------"
  cat "$create_log"
  echo "--------------------------------------------------------------------"
  rm -f "$create_log" "$create_out"
  exit 1
fi

if [ "${MC_VERBOSE:-0}" == "1" ]; then
  cat "$create_log"
fi
rm -f "$create_log"

external_ip=$(jq -r '.[].networkInterfaces[0].accessConfigs[0].natIP' < "$create_out")
rm -f "$create_out"
echo " 完了"

# The VM is up, but the container still has to be pulled and the world
# generated. Probe UDP 19132 from here until the server actually answers,
# so the script does not report success before you can join.
#
# The notice comes before the wait rather than with the prompt itself: the wait
# runs for minutes, and a screen that is not moving is easy to walk away from.
cat <<EOS

※ サーバー起動完了時、サーバー情報のファイルダウンロードが促されます。
   こちらをダウンロードし、保管してください。

EOS
echo -n "マインクラフト起動中 "

ping_info=$(mktemp)

if wait_for_server "$external_ip" 900 "$ping_info"; then
  # The server reports its own name and version, so take them from there rather
  # than from what was typed: this is what a client will actually see.
  MC_VERSION=""
  if [ -s "$ping_info" ]; then
    # shellcheck disable=SC1090
    . "$ping_info"
  fi
  rm -f "$ping_info"

  # Everything needed to join, and to manage the server later, gathered in one
  # place. CloudShell's home directory is not permanent, so the file is handed
  # to the browser as well.
  info_file="${HOME}/minecraft-server-info.txt"
  cat > "$info_file" <<EOS
====================================================================
 Minecraft サーバー情報
====================================================================
 作成日時 : $(date '+%Y-%m-%d %H:%M:%S %Z')

--------------------------------------------------------------------
 接続情報   ※ 一緒に遊ぶ人に伝える内容
--------------------------------------------------------------------
 サーバーアドレス : ${external_ip}
 ポート           : 19132
 サーバー名       : ${server_name:-ydak}
 エディション     : 統合版 (Bedrock)
 バージョン       : ${MC_VERSION:-(取得できませんでした)}

--------------------------------------------------------------------
 ゲーム設定
--------------------------------------------------------------------
 ゲームモード : ${game_mode:-survival}
 難易度       : ${difficulty:-normal}
 チート       : ${allow_cheat:-false}
 参加者の権限 : ${permission:-member}
 最大人数     : ${max_players:-2}
 シード値     : ${seed:-(ランダム)}
 描画距離     : 5 チャンク (既定の 32 から下げています)
 放置切断     : 5 分 (既定の 30 分から下げています)

--------------------------------------------------------------------
 管理情報   ※ 自分用。共有する必要はありません
--------------------------------------------------------------------
 プロジェクト ID  : ${project_id}
 プロジェクト番号 : ${project_num}
 インスタンス名   : minecraft
 ゾーン           : us-west1-b
 マシンタイプ     : e2-micro

--------------------------------------------------------------------
 操作方法
--------------------------------------------------------------------
 CloudShell で下記を実行し、メニューから選びます。

   curl -fsSL https://daylifehack.com/mc | bash

   create  : サーバーを作成する
   update  : マインクラフトとホストを更新する
   backup  : ワールドをバックアップする
   restore : ワールドを復元する
   delete  : サーバーを削除する (ワールドも消えます)

--------------------------------------------------------------------
 注意
--------------------------------------------------------------------
 ・許可リストは無効です。この IP を知っていれば誰でも参加できます。
 ・サーバーを停止・起動すると IP アドレスが変わります。
   再起動 (reboot) では変わりません。
 ・無料枠で動かせるサーバーは 1 台までです。
 ・下り通信は 1GB/月 まで無料です。超過分は約 \$0.12/GB です。
   目安として 1 人が 1 時間遊ぶとおよそ 36MB です。
====================================================================
EOS

  cat <<EOS

すべて完了しました！

################################################################################
${external_ip}
################################################################################

 ポート : 19132
 上記のアドレスとポートで、マインクラフトから接続できます。

 許可リストは無効です。この IP を知っていれば誰でも参加できます。

EOS

  # `cloudshell download` is missing outside CloudShell, and a refused download
  # should not fail a successful build, so neither case is treated as an error.
  if command -v cloudshell > /dev/null; then
    cat <<EOS
接続情報を ${info_file} に保存しました。
ブラウザにダウンロードの確認が表示されます。

EOS
    cloudshell download "$info_file" || true
  else
    cat <<EOS
接続情報を ${info_file} に保存しました。

EOS
  fi
else
  rm -f "$ping_info"
  cat <<EOS

[WARN] The server did not answer within 15 minutes.
       (15分以内にサーバーが応答しませんでした。)

The VM itself was created, so the container may still be starting.
Check the log with the following command.
(VM の作成は完了しています。コンテナ起動中の可能性があるためログを確認して下さい。)

  gcloud compute ssh --quiet minecraft --zone=us-west1-b --command='docker logs mc-server | tail -30'

################################################################################
${external_ip}
################################################################################

EOS
fi
