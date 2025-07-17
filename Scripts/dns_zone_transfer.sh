#./dns_zone_transfer.sh domain.com IP
#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <domain.com> <nameserver_IP>"
    exit 1
fi

DOMAIN="$1"
NS_IP="$2"
SUCCESS_FILE="subdomain_zone_transfer_success.txt"
FAIL_FILE="subdomain_zone_transfer_failed.txt"
TEMP_DIR="zone_transfer_temp"

mkdir -p "$TEMP_DIR"
> "$SUCCESS_FILE"
> "$FAIL_FILE"

# Use associative array to avoid duplicate checks
declare -A CHECKED

echo "[*] Starting recursive zone transfer checks for $DOMAIN @ $NS_IP"

function perform_zone_transfer() {
    local ZONE="$1"
    local CURRENT_NS_IP="$2"

    if [[ ${CHECKED["$ZONE"]+exists} ]]; then
        return
    fi
    CHECKED["$ZONE"]=1

    echo "[*] Attempting zone transfer for $ZONE @ $CURRENT_NS_IP"
    dig axfr "$ZONE" @"$CURRENT_NS_IP" > "$TEMP_DIR/$ZONE.zone"

    if grep -q "Transfer failed" "$TEMP_DIR/$ZONE.zone" || grep -q "XFR size: 0" "$TEMP_DIR/$ZONE.zone"; then
        echo "[!] Zone transfer failed for $ZONE"
        echo "$ZONE" >> "$FAIL_FILE"
    else
        echo "[+] Zone transfer succeeded for $ZONE"
        echo "$ZONE" >> "$SUCCESS_FILE"

        # Extract subdomains and recurse
        awk '/IN[[:space:]]+A[[:space:]]+/ {print $1}' "$TEMP_DIR/$ZONE.zone" | sed 's/\.$//' | sort -u | while read -r SUBDOMAIN; do
            perform_zone_transfer "$SUBDOMAIN" "$CURRENT_NS_IP"
        done
    fi
}

# Start recursive check with initial domain
perform_zone_transfer "$DOMAIN" "$NS_IP"

rm -r "$TEMP_DIR"

echo "[*] Recursive zone transfer checks complete."
echo "[*] Success list saved to: $SUCCESS_FILE"
echo "[*] Fail list saved to: $FAIL_FILE"
