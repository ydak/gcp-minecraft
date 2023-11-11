# gcp-minecraft

Script to easily create a Minecraft server on Google Cloud.
Internally, this uses a Docker container.

## Features

* Uses the "Always free" range of Google Cloud
* You can keep the Minecraft server running semi-permanently

## Requirements

* Your Google Cloud Account

## Usage

### Create Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
git clone https://github.com/ydak/gcp-minecraft.git ; ./gcp-minecraft/create.sh
```

### Update Minecraft server

If you are unable to play due to a mismatched Minecraft version, run this.

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
git clone https://github.com/ydak/gcp-minecraft.git ; git -C ./gcp-minecraft pull ; ./gcp-minecraft/update.sh
```

### Delete Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
git clone https://github.com/ydak/gcp-minecraft.git ; git -C ./gcp-minecraft pull ; ./gcp-minecraft/delete.sh
```
