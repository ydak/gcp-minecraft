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

```
This tool needs to create the directory [/home/<USER_NAME>/.ssh] before being able
 to generate SSH keys.

Do you want to continue (Y/n)?
```

In the following statement, press Enter without typing anything.
```
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
```

### Create Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/install.sh | bash
```

### Update Minecraft server

If you are unable to play due to a mismatched Minecraft version, run this.

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/install.sh | bash -s -- update
```

### Delete Minecraft server

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/install.sh | bash -s -- delete
```
