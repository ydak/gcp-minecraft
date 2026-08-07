#!/usr/bin/env bash
#
# Bootstrap for gcp-minecraft.
#
#   curl -fsSL https://raw.githubusercontent.com/ydak/gcp-minecraft/main/install.sh | bash
#
# The scripts in this repository source functions.sh and const.sh from their own
# directory, so a single file cannot be piped straight into a shell. This
# downloads the repository into a temporary directory and hands over to the
# requested script.
#
set -e

REPO="ydak/gcp-minecraft"
REF="${REF:-main}"
ACTION="${1:-create}"

usage() {
  cat <<EOS
Usage (CloudShell):

  # Create a Minecraft server (マインクラフトサーバーを作成)
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash

  # Update (マインクラフトを更新)
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- update

  # Delete (マインクラフトサーバーを削除)
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- delete

Set REF to use a branch or tag other than main.
(REF を指定すると main 以外のブランチ・タグを利用できます。)
EOS
}

case "$ACTION" in
  create | update | delete) ;;
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

if [ ! -f "${work_dir}/${ACTION}.sh" ]; then
  echo "[ERROR] ${ACTION}.sh was not found in ${REPO} (${REF})."
  echo "        (${ACTION}.sh が見つかりませんでした。)"
  exit 1
fi

# When this script is piped into bash, stdin is the pipe rather than the
# terminal. The prompts in create.sh / delete.sh would then read whatever is
# left of this script, or hit EOF immediately, so reconnect stdin to the
# terminal before handing over. Skipped when no terminal is available.
if [ -c /dev/tty ] && (exec < /dev/tty) 2> /dev/null; then
  exec < /dev/tty
fi

bash "${work_dir}/${ACTION}.sh"
