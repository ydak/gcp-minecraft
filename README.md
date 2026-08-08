# gcp-minecraft

Script to easily create a Minecraft server on Google Cloud.
Internally, this uses a Docker container.

## Features

* Uses the "Always free" range of Google Cloud
* You can keep the Minecraft server running semi-permanently

## Requirements

* Your Google Cloud Account

## Usage

1. Open CloudShell in Google Cloud
1. Execute the following command

```bash
curl -fsSL https://daylifehack.com/mc | bash
```

1. Select what you want to do from the menu

```
-*-*-*-*- [ACTION (操作を選択)] -*-*-*-*-
[1] create (マインクラフトサーバーを作成)
[2] update (マインクラフトを更新)
[3] delete (マインクラフトサーバーを削除)
Select action (Default: 1):
```

| Action | Description |
| --- | --- |
| `create` | Create a Minecraft server. |
| `update` | Update Minecraft. Run this if you are unable to play due to a mismatched version. |
| `delete` | Delete the Minecraft server. **The world data is deleted along with it.** |

The action can also be given directly, which skips the menu.

```bash
curl -fsSL https://daylifehack.com/mc | bash -s -- update
```

`https://daylifehack.com/mc` redirects to `mc.sh` in this repository.
The direct URL also works if you prefer it.

```bash
curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/mc.sh | bash
```

## Notes

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
