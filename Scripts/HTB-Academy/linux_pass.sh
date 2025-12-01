#!/bin/bash
#change the password and username with needed
# Default values
PASSWORD="HTB_@cademy_stdnt!"
USERNAME="htb-student"

# Parse arguments
while getopts "i:" opt; do
  case $opt in
    i)
      TARGET_IP="$OPTARG"
      ;;
    *)
      echo "Usage: $0 -i <IP>"
      exit 1
      ;;
  esac
done

# Check if IP is provided
if [ -z "$TARGET_IP" ]; then
  echo "Error: IP address not provided."
  echo "Usage: $0 -i <IP>"
  exit 1
fi

# Execute SSH command
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ${USERNAME}@${TARGET_IP}
