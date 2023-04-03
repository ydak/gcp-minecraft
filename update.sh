#!/usr/bin/env bash
set -e

echo "==================== Start minecraft update ===================="
echo "Updating ..."
gcloud compute ssh --zone "us-west1-b" "minecraft" --command="docker pull itzg/minecraft-bedrock-server:latest && docker restart mc-server"
echo "Minecraft has been updated!"
echo "==================== End minecraft update ===================="
