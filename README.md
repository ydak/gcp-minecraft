# gcp-minecraft

Script to easily create a Minecraft server on Google Cloud.
Internally, this uses a Docker container.

## Features

* Uses the "Always free" range of Google Cloud
* You can keep the Minecraft server running semi-permanently

## Requirements

* Your Google Cloud Account

## Usage

※If the following SSH key creation statement appears, enter "Y" to continue.

```shell
This tool needs to create the directory [/home/<USER_NAME>/.ssh] before being able
 to generate SSH keys.

Do you want to continue (Y/n)?
```

### Create Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
rm -rf /tmp/ydak-mc ; git clone https://github.com/ydak/gcp-minecraft /tmp/ydak-mc ; /tmp/ydak-mc/create.sh
```

### Update Minecraft server

If you are unable to play due to a mismatched Minecraft version, run this.

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
rm -rf /tmp/ydak-mc ; git clone https://github.com/ydak/gcp-minecraft /tmp/ydak-mc ; /tmp/ydak-mc/update.sh
```

### Delete Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
rm -rf /tmp/ydak-mc ; git clone https://github.com/ydak/gcp-minecraft /tmp/ydak-mc ; /tmp/ydak-mc/delete.sh
```
