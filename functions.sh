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
