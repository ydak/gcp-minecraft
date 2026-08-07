#!/usr/bin/env bash
#
# Bootstrap for gcp-minecraft.
#
#   curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/mc.sh | bash
#
# The scripts in this repository source functions.sh and const.sh from their own
# directory, so a single file cannot be piped straight into a shell. This
# downloads the repository into a temporary directory, asks what to do, and
# hands over to the matching script.
#
set -e

REPO="ydak/gcp-minecraft"
REF="${REF:-main}"
ACTION="${1:-}"

action_list=(create update delete)

usage() {
  cat <<EOS
Usage (CloudShell):

  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/mc.sh | bash

Then pick create / update / delete from the menu.
(その後、メニューから create / update / delete を選択します。)

An action can also be given directly, which skips the menu.
(操作を引数で直接指定すると、メニューを省略できます。)

  ... | bash -s -- create
  ... | bash -s -- update
  ... | bash -s -- delete

Set REF to use a branch or tag other than main.
(REF を指定すると main 以外のブランチ・タグを利用できます。)
EOS
}

case "$ACTION" in
  "" | create | update | delete) ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  *)
    echo "[ERROR] Unknown action: $ACTION"
    echo "        (不明な操作です。create / update / delete のいずれかを指定して下さい。)"
    echo ""
    usage
    exit 1
    ;;
esac

for cmd in curl tar; do
  if ! command -v "$cmd" > /dev/null; then
    echo "[ERROR] '$cmd' is required but was not found."
    echo "        ('$cmd' が見つかりません。)"
    exit 1
  fi
done

# When this script is piped into a shell, stdin is the pipe rather than the
# terminal. Both the menu below and the prompts in create.sh would then read
# whatever is left of this script, or hit EOF immediately. Reconnect stdin to
# the terminal before anything asks a question. Skipped when there is no
# terminal, which is handled where the menu is shown.
if [ -c /dev/tty ] && (exec < /dev/tty) 2> /dev/null; then
  exec < /dev/tty
fi

echo "==================== gcp-minecraft ===================="

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "Downloading ${REPO} (${REF}) ..."

# pipefail is scoped to this subshell so that a failed download is caught here
# rather than being masked by tar's exit status.
if ! (set -o pipefail
      curl -fsSL "https://codeload.github.com/${REPO}/tar.gz/${REF}" \
        | tar xz -C "$work_dir" --strip-components=1); then
  echo "[ERROR] Failed to download ${REPO} (${REF})."
  echo "        (ダウンロードに失敗しました。REF の指定を確認して下さい。)"
  exit 1
fi

# shellcheck source=functions.sh
. "${work_dir}/functions.sh"

# ACTION ==========
if [ "$ACTION" == "" ]; then
  if [ ! -t 0 ]; then
    echo "[ERROR] No terminal is available, so the menu cannot be shown."
    echo "        (端末が無いためメニューを表示できません。)"
    echo "        Pass the action directly: ... | bash -s -- create"
    echo "        (操作を引数で指定して下さい。)"
    exit 1
  fi

  cat <<EOS

-*-*-*-*- [ACTION (操作を選択)] -*-*-*-*-
[1] create (マインクラフトサーバーを作成)
[2] update (マインクラフトを更新)
[3] delete (マインクラフトサーバーを削除)
EOS
  echo -n "Select action (Default: 1): "
  read -r action_num
  if [ "$action_num" == "" ]; then action_num=1 ; fi
  num_validation "$action_num" 3
  ACTION=${action_list[$action_num-1]}
fi

if [ ! -f "${work_dir}/${ACTION}.sh" ]; then
  echo "[ERROR] ${ACTION}.sh was not found in ${REPO} (${REF})."
  echo "        (${ACTION}.sh が見つかりませんでした。)"
  exit 1
fi

bash "${work_dir}/${ACTION}.sh"
