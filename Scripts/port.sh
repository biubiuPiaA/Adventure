#!/bin/bash

#extract unique ports from nmap scanning result
# Check if Nmap output file is provided as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <nmap_output_file>"
    exit 1
fi

# Check if the file exists
if [ ! -f "$1" ]; then
    echo "File not found: $1"
    exit 1
fi

# Extract port numbers using awk and remove the "/tcp" suffix
port_numbers=$(awk '/^[0-9]+\/tcp/ { printf "%s,",$1 } END { printf "\b\n" }' "$1" | sed 's,/tcp,,g')

# Display the extracted port numbers
echo "Port numbers found in $1:"
echo "$port_numbers"
