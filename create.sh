#!/usr/bin/env bash
set -e

script_dir=$(dirname ${0})
. $script_dir/functions.sh
. $script_dir/const.sh

echo "==================== Start create minecraft server  ===================="

# GOOGLE CLOUD ==========
echo -n "Setting Google Cloud info ..."
project_id=$(gcloud config get project)
project_num=$(gcloud projects list --filter="$project_id" --format="value(PROJECT_NUMBER)")
gcloud config set project $project_id

cat <<EOS

-*-*-*-*- [GOOGLE CLOUD (Google Cloud の情報確認)] -*-*-*-*-
プロジェクト ID  : $project_id
プロジェクト番号 : $project_num

上記の Google Cloud でマインクラフトサーバーを作成します。
EOS

echo -n "よろしいですか? [y/N]: "
read -r gcp_info
if [ "$gcp_info" != "y" ]; then exit 1 ; fi

# SERVER NAME ==========
cat <<EOS

-*-*-*-*- [SERVER NAME (マインクラフトサーバー名を自由に決めて下さい)] -*-*-*-*-
EOS
echo -n "Server name (Default: ydak): "
read -r server_name

# GAME MODE ==========
cat <<EOS

-*-*-*-*- [GAME MODE (ゲームモードを選択)] -*-*-*-*-
1. survival (サバイバル)
2. creative (クリエイティブ)
3. adventure (アドベンチャー)
EOS
echo -n "Select game mode (Default: survival): "
read -r game_mode_num
if [ "$game_mode_num" == "" ]; then game_mode_num=1 ; fi
num_validation $game_mode_num 3
game_mode=${game_mode_list[$game_mode_num-1]}

# DIFFICULTY ==========
cat <<EOS

-*-*-*-*- [DIFFICULTY (難易度を選択)] -*-*-*-*-
1. peaceful (ピースフル)
2. easy (イージー)
3. normal (ノーマル)
4. hard (ハード)
EOS
echo -n "Difficulty (Default: normal): "
read -r difficulty_num
if [ "$difficulty_num" == "" ]; then difficulty_num=3 ; fi
num_validation $difficulty_num 4
difficulty=${difficulty_list[$difficulty_num-1]}

# CHEAT ==========
cat <<EOS

-*-*-*-*- [CHEAT (チートを有効にするかどうか)] -*-*-*-*-
1. ON (有効)
2. OFF (無効)
EOS
echo -n "Allow cheat? (Default: OFF): "
read -r allow_cheat_num
if [ "$allow_cheat_num" == "" ]; then allow_cheat_num=2 ; fi
num_validation $allow_cheat_num 2
allow_cheat=${allow_cheat_list[$allow_cheat_num-1]}

# PERMISSION ==========
cat <<EOS

-*-*-*-*- [PERMISSION (サーバーに参加するユーザー全員の権限)] -*-*-*-*-
1. visitor (訪問者)
2. member (メンバー)
3. operator (管理者)
EOS
echo -n "Default permission (Default: member): "
read -r permission_num
if [ "$permission_num" == "" ]; then permission_num=2 ; fi
num_validation $permission_num 3
permission=${permission_num_list[$permission_num-1]}

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

echo "Configuration is OK. The next step is to create a minecraft server."
echo "(サーバー設定が完了しました。マインクラフトサーバーの作成を開始します。)"

echo "Enabling compute.googleapis.com ..."
gcloud services enable compute.googleapis.com

# firewall =====================================================================
echo "Checking Firewall ..."
fw_minecraft=$(gcloud compute firewall-rules list --format="json" | jq -r '.[] | select(.name=="minecraft")')

if [ -z "$fw_minecraft" ]; then
  echo "Firewall minecraft is not found. Creating Firewall for Minecraft ..."
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
echo "Firewall creation complete!"

# GCE ==========================================================================
echo "Checking latest COS image ..."
image=$(gcloud compute images list --format="json" | jq -r '.[] | select(.family | test("cos-stable")) | .selfLink' | sed -E 's/.*(projects.*)/\1/')
echo "COS image check complete."

echo "Creating server for minecraft ..."

external_ip=$(gcloud compute instances create minecraft \
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
  --create-disk=auto-delete=yes,boot=yes,device-name=minecraft,image=$image,mode=rw,size=10,type="projects/$project_id/zones/us-west1-b/diskTypes/pd-standard" --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
  --reservation-affinity=any \
  --metadata=startup-script="#!/bin/bash
mkdir /var/minecraft && \
cd /var/minecraft/ && \
docker volume create mc-volume && \
docker run -d -it --name mc-server --restart=always -e EULA=TRUE -e SERVER_NAME=${server_name:-ydak} -e GAMEMODE=${game_mode:-survival} -e DIFFICULTY=${difficulty:-normal} -e ALLOW_CHEATS=${allow_cheat:-false} -e DEFAULT_PLAYER_PERMISSION_LEVEL=${permission:-member} -e LEVEL_SEED=$seed -p 19132:19132/udp -v mc-volume:/data itzg/minecraft-bedrock-server:latest
" | jq -r '.[].networkInterfaces[0].accessConfigs[0].natIP')

echo "Creating server complete!"

cat <<EOS

All Done!!
 (すべて完了しました！！)

Wait for a minute and access the minecraft!
 (数分後にマインクラフトへアクセスできます)

You can access Minecraft using the following IP address!
(下記のIPアドレスを使用してマインクラフトにアクセス可能です！)

################################################################################
${external_ip}
################################################################################

EOS
echo "==================== End create minecraft server  ===================="
