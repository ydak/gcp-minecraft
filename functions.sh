################################################################################
# Prints a dot a second until the given process exits.
#
# Arguments:
#   1: Process id to wait for
# Returns:
#   The exit status of that process
################################################################################
function wait_with_dots() {
  local pid=$1
  local status=0

  while kill -0 "$pid" 2> /dev/null; do
    echo -n "."
    sleep 1
  done

  # The process has already gone, but bash keeps its status until it is reaped.
  wait "$pid" || status=$?
  return $status
}

################################################################################
# Prints a dot a second for the given number of seconds.
#
# Arguments:
#   1: Seconds to wait
# Returns:
#   None
################################################################################
function sleep_with_dots() {
  local seconds=$1
  local i

  for ((i = 0; i < seconds; i++)); do
    echo -n "."
    sleep 1
  done
}

################################################################################
# Runs a command, showing a short label instead of its output.
#
# gcloud prints tables, resource URLs and progress spinners that mean nothing to
# someone who just wants a Minecraft server, and a wall of them reads as
# something having gone wrong. The output is captured and only printed when the
# command fails, which is the point at which it becomes worth reading.
#
# Set MC_VERBOSE=1 to pass everything straight through instead.
#
# Arguments:
#   1: Label shown to the user
#   2+: Command to run
# Returns:
#   The exit status of the command
################################################################################
function run_step() {
  local label=$1
  shift

  if [ "${MC_VERBOSE:-0}" == "1" ]; then
    echo "  $label ..."
    "$@"
    return $?
  fi

  local log status
  log=$(mktemp)
  echo -n "  $label "

  # Run in the background so a dot can be printed every second. Some of these
  # calls take minutes, and a screen that has not moved reads as a hang.
  "$@" > "$log" 2>&1 &
  status=0
  wait_with_dots $! || status=$?

  if [ "$status" -eq 0 ]; then
    echo " 完了"
    rm -f "$log"
    return 0
  fi

  echo " 失敗"
  echo ""
  echo "[ERROR] 処理に失敗しました。(The step above failed.)"
  echo "--------------------------------------------------------------------"
  cat "$log"
  echo "--------------------------------------------------------------------"
  rm -f "$log"
  return $status
}

################################################################################
# Receives a string and check if it is a specified number.
# If it is not a valid number, exits with error code 1.
#
# Arguments:
#   1: Received input
#   2: Valid max number
# Returns:
#   None
################################################################################
function num_validation() {
  local received=$1
  local max_num=$2

  if [ "$received" != "" ]; then
    if [[ ! ("$received" =~ ^[1-$max_num]$) ]]; then
      echo "[ERROR] Enter valid number. (数字を正しく入力して下さい。)"
      exit 1
    fi
  fi
}

################################################################################
# Receives a string and checks if it is a positive integer.
# Used where the answer is not a menu choice, so num_validation, which only
# accepts a single digit within a range, does not fit.
# If it is not valid, exits with error code 1.
#
# Arguments:
#   1: Received input
# Returns:
#   None
################################################################################
function positive_num_validation() {
  local received=$1

  if [[ ! ("$received" =~ ^[1-9][0-9]*$) ]]; then
    echo "[ERROR] Enter a number of 1 or more. (1 以上の数字を入力して下さい。)"
    exit 1
  fi
}

################################################################################
# Waits until the Bedrock server answers a RakNet unconnected ping.
# Prints a dot every second while waiting.
#
# This probes UDP 19132 from the outside, so it covers the whole path at once:
# the firewall rule, the container, and the server itself. No SSH key needed.
#
# Arguments:
#   1: External IP address of the server
#   2: Timeout in seconds
#   3: Optional path to write the answered details to, as shell assignments
# Returns:
#   0 if the server answered, 1 on timeout
################################################################################
function wait_for_server() {
  local ip=$1
  local timeout=$2
  local info_path=${3:-}

  if ! command -v python3 > /dev/null; then
    echo ""
    echo "[WARN] python3 not found. Skipping the health check."
    echo "       (python3 が無いためヘルスチェックを省略します。)"
    return 0
  fi

  python3 - "$ip" "$timeout" "$info_path" <<'PYEOF'
import shlex
import socket
import struct
import sys
import time

# OFFLINE_MESSAGE_DATA_ID. Every RakNet offline packet carries this.
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
PORT = 19132

ip = sys.argv[1]
deadline = time.time() + int(sys.argv[2])
info_path = sys.argv[3] if len(sys.argv) > 3 else ""

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
# Kept under the one second tick so that the probe and the wait together still
# land on a dot a second, rather than drifting out to two.
sock.settimeout(0.8)
next_tick = time.time()

while time.time() < deadline:
    # ID_UNCONNECTED_PING: id(1) + time(8) + magic(16) + client guid(8)
    ping = b"\x01" + struct.pack(">Q", int(time.time() * 1000)) + MAGIC + struct.pack(">Q", 0)
    try:
        sock.sendto(ping, (ip, PORT))
        data, _ = sock.recvfrom(4096)
    except Exception:
        data = b""

    # ID_UNCONNECTED_PONG: id(1) + time(8) + server guid(8) + magic(16) + motd
    if data[:1] == b"\x1c" and len(data) > 35:
        length = struct.unpack(">H", data[33:35])[0]
        fields = data[35:35 + length].decode("utf-8", "replace").split(";")
        print("")
        if len(fields) >= 6:
            print("  Server name : %s" % fields[1])
            print("  Version     : %s" % fields[3])
            print("  Players     : %s/%s" % (fields[4], fields[5]))
            # The MOTD is whatever the operator typed, so quote every value
            # before it is sourced back into the shell.
            if info_path:
                lines = [
                    "MC_NAME=" + shlex.quote(fields[1]),
                    "MC_VERSION=" + shlex.quote(fields[3]),
                    "MC_MAX_PLAYERS=" + shlex.quote(fields[5]),
                    "",
                ]
                with open(info_path, "w", encoding="utf-8") as fh:
                    fh.write(chr(10).join(lines))
        sys.exit(0)

    sys.stdout.write(".")
    sys.stdout.flush()
    next_tick += 1.0
    remaining = next_tick - time.time()
    if remaining > 0:
        time.sleep(remaining)

print("")
sys.exit(1)
PYEOF
}
