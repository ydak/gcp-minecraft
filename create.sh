#!/usr/bin/env bash
set -e

echo "==================== Start create minecraft server  ===================="

echo -n "Server name (Default: ydak): "
read -r server_name

echo -n "Game mode (Default: survival) [survival or creative or adventure]: "
read -r game_mode
if [ "$game_mode" != "" ] && [ "$game_mode" != "survival" ] && [ "$game_mode" != "creative" ] && [ "$game_mode" != "adventure" ]; then
  echo "Enter correct game mode [survival] or [creative] or [adventure]."
  exit 1
fi

echo -n "Difficulty (Default: normal) [peaceful or easy or normal or hard]: "
read -r difficulty
if [ "$difficulty" != "" ] && [ "$difficulty" != "peaceful" ] && [ "$difficulty" != "easy" ] && [ "$difficulty" != "normal" ] && [ "$difficulty" != "hard" ]; then
  echo "Enter correct game mode [peaceful] or [easy] or [normal] or [hard]."
  exit 1
fi

echo -n "Allow cheat? (Default: false) [true or false]: "
read -r allow_cheat
if [ "$allow_cheat" != "" ] && [ "$allow_cheat" != "true" ] && [ "$allow_cheat" != "false" ]; then
  echo "Enter allow cheat [true] or [false]"
  exit 1
fi

echo -n "Default member permission (Default: member) [visitor or member or operator]: "
read -r permission
if [ "$permission" != "" ] && [ "$permission" != "visitor" ] && [ "$permission" != "member" ] && [ "$permission" != "operator" ]; then
  echo "Enter correct permission [visitor] or [member] or [operator]"
  exit 1
fi

echo -n "Seed (Default: random): "
read -r seed
if [ "$seed" != "" ]; then
  if [[ ! ("$seed" =~ ^[-0-9][0-9]+$) ]]; then
    echo "Enter correct number for seed."
    exit 1
  fi
fi

echo "Configuration is OK. The next step is to create a minecraft server."

project_id=$(gcloud projects list --format="json" | jq -r '.[].projectId')
project_num=$(gcloud projects list --format="json" | jq -r '.[].projectNumber')

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
