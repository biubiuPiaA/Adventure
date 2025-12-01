#!/bin/bash
# for windows rdp connection
# ✅ Function to display usage instructions
usage() {
  echo "Usage: $0 -i <IP_ADDRESS>"
  exit 1
}

# ✅ Parse the '-i' flag for the IP address
while getopts ":i:" opt; do
  case ${opt} in
    i )
      IP="$OPTARG"
      ;;
    \? )
      usage
      ;;
  esac
done

# ✅ Check if IP is provided
if [ -z "$IP" ]; then
  usage
fi

# ✅ Inform the user of the connection
echo "[+] Connecting to $IP via RDP..."

# ✅ Execute rdesktop with automatic 'yes' response
yes "yes" | rdesktop -u htb-student -p HTB_@cademy_stdnt! "$IP"
