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
# Waits until the Bedrock server answers a RakNet unconnected ping.
# Prints a dot every second while waiting.
#
# This probes UDP 19132 from the outside, so it covers the whole path at once:
# the firewall rule, the container, and the server itself. No SSH key needed.
#
# Arguments:
#   1: External IP address of the server
#   2: Timeout in seconds
# Returns:
#   0 if the server answered, 1 on timeout
################################################################################
function wait_for_server() {
  local ip=$1
  local timeout=$2

  if ! command -v python3 > /dev/null; then
    echo ""
    echo "[WARN] python3 not found. Skipping the health check."
    echo "       (python3 が無いためヘルスチェックを省略します。)"
    return 0
  fi

  python3 - "$ip" "$timeout" <<'PYEOF'
import socket
import struct
import sys
import time

# OFFLINE_MESSAGE_DATA_ID. Every RakNet offline packet carries this.
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
PORT = 19132

ip = sys.argv[1]
deadline = time.time() + int(sys.argv[2])

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(1.0)

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
        sys.exit(0)

    sys.stdout.write(".")
    sys.stdout.flush()
    time.sleep(1)

print("")
sys.exit(1)
PYEOF
}
