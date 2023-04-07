#!/usr/bin/env bash
set -e

echo "==================== Start create minecraft server  ===================="

echo -n "Project number: "
read -r project_num

echo -n "Project id: "
read -r project_id

echo -n "Server name (Default: ydak): "
read -r server_name

# GAME MODE ==========
cat << EOS
[GAME MODE]
1. survival (サバイバル)
2. creative (クリエイティブ)
3. adventure (アドベンチャー)
EOS
echo -n "Select game mode (Default: survival): "
read -r game_mode_num
if [ "$game_mode_num" != "" ] && [ "$game_mode_num" != "1" ] && [ "$game_mode_num" != "2" ] && [ "$game_mode_num" != "3" ]; then
  echo "[ERROR] Enter correct number 1 or 2 or 3."
  exit 1
fi
if [ "$game_mode_num" == "1" ]; then
  game_mode=survival
fi
if [ "$game_mode_num" == "2" ]; then
  game_mode=creative
fi
if [ "$game_mode_num" == "3" ]; then
  game_mode=adventure
fi

# DIFFICULTY ==========
cat << EOS
[DIFFICULTY]
1. peaceful (平和)
2. easy (簡単)
3. normal (普通)
4. hard (難しい)
EOS
echo -n "Difficulty (Default: normal): "
read -r difficulty_num
if [ "$difficulty_num" != "" ] && [ "$difficulty_num" != "1" ] && [ "$difficulty_num" != "2" ] && [ "$difficulty_num" != "3" ] && [ "$difficulty_num" != "4" ]; then
  echo "[ERROR] Enter correct number 1 or 2 or 3 or 4."
  exit 1
fi
if [ "$difficulty_num" == "1" ]; then
  difficulty=peaceful
fi
if [ "$difficulty_num" == "2" ]; then
  difficulty=easy
fi
if [ "$difficulty_num" == "3" ]; then
  difficulty=normal
fi
if [ "$difficulty_num" == "4" ]; then
  difficulty=hard
fi

# ALLOW CHEAT ==========
cat << EOS
[ALLOW CHEAT]
1. yes (有効)
2. no (無効)
EOS
echo -n "Allow cheat? (Default: no): "
read -r allow_cheat_num
if [ "$allow_cheat_num" != "" ] && [ "$allow_cheat_num" != "1" ] && [ "$allow_cheat_num" != "2" ]; then
  echo "[ERROR] Enter correct number 1 or 2"
  exit 1
fi
if [ "$allow_cheat_num" == "1" ]; then
  allow_cheat=true
fi
if [ "$allow_cheat_num" == "2" ]; then
  allow_cheat=false
fi

# ALLOW CHEAT ==========
cat << EOS
[ALLOW CHEAT]
1. visitor (訪問者)
2. member (メンバー)
3. operator (管理者)
EOS
echo -n "Default permission (Default: member): "
read -r permission_num
if [ "$permission_num" != "" ] && [ "$permission_num" != "1" ] && [ "$permission_num" != "2" ] && [ "$permission_num" != "3" ]; then
  echo "[ERROR] Enter correct number 1 or 2 or 3"
  exit 1
fi

echo -n "Seed (Default: random): "
read -r seed
if [ "$seed" != "" ]; then
  if [[ ! ("$seed" =~ ^[-0-9][0-9]+$) ]]; then
    echo "[ERROR] Enter correct number for seed."
    exit 1
  fi
fi

echo "Configuration is OK. The next step is to create a minecraft server."

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
echo "Firewall creation done."

# GCE ==========================================================================
echo "Checking latest COS image ..."
image=$(gcloud compute images list --format="json" | jq -r '.[] | select(.family | test("cos-stable")) | .selfLink' | sed -E 's/.*(projects.*)/\1/')
echo "COS image Check Done."

echo "Creating GCE for minecraft ..."

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

echo "All Done!! Wait for 3 minutes and access the minecraft!"
echo ""
echo "##########################################################################"
echo "You can access Minecraft using the [$external_ip] server IP address."
echo "##########################################################################"
echo ""
echo "==================== End create minecraft server  ===================="
