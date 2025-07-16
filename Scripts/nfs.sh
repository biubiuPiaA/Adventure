# This script will auto install for the related NFS tools 
#./nfs.sh -i IP 
#./nfs.sh --unmount
# -y: auto yes for the prompting (nfs.sh i IP -y, --unmount -y)
# when script respond with failed to unmount xx, wait a few seconds and proceed for another try or try few more time for it
#!/bin/bash

CONFIG_FILE="$HOME/.nfs_mount_config"
REQUIRED_PKG="nfs-common"
VERBOSE=false
UNMOUNT=false
TARGET_IP=""
MOUNT_DIR=""
YES_TO_ALL=false
DEFAULT_MOUNT_DIR="/home/kali/all/tmp/mount"

RED='\e[31m'
GREEN='\e[32m'
NC='\e[0m' # No Color

function log() {
    if $VERBOSE; then
        echo -e "$@"
    fi
}

function check_dependencies() {
    if ! dpkg -s $REQUIRED_PKG &> /dev/null; then
        echo "[*] $REQUIRED_PKG not found. Installing..."
        sudo apt update && sudo apt install -y $REQUIRED_PKG
    else
        log "[*] $REQUIRED_PKG already installed."
    fi
}

function load_or_set_mount_dir() {
    if [ -f "$CONFIG_FILE" ]; then
        MOUNT_DIR=$(cat "$CONFIG_FILE")
    elif $YES_TO_ALL; then
        MOUNT_DIR="$DEFAULT_MOUNT_DIR"
        echo "$MOUNT_DIR" > "$CONFIG_FILE"
        echo -e "${GREEN}[+] Using default mount folder: $MOUNT_DIR${NC}"
    else
        set_new_mount_dir
    fi
}

function confirm_or_update_mount_dir() {
    echo "[*] Current mount folder path: $MOUNT_DIR"
    if ! $YES_TO_ALL; then
        read -p "Do you want to keep using this mount folder? [Y/n] " answer
        if [[ "$answer" =~ ^[Nn]$ ]]; then
            set_new_mount_dir
        fi
    fi
}

function confirm_or_update_mount_dir_unmount() {
    echo "[*] Current mount folder path: $MOUNT_DIR"
    if ! $YES_TO_ALL; then
        read -p "Is this the correct folder to unmount from? [Y/n] " answer
        if [[ "$answer" =~ ^[Nn]$ ]]; then
            set_new_mount_dir
        fi
    fi
}

function set_new_mount_dir() {
    if $YES_TO_ALL; then
        MOUNT_DIR="$DEFAULT_MOUNT_DIR"
        echo "$MOUNT_DIR" > "$CONFIG_FILE"
        echo -e "${GREEN}[+] Using default mount folder: $MOUNT_DIR${NC}"
    else
        read -p "Enter new mount folder path (absolute path, no trailing slash): " MOUNT_DIR
        echo "$MOUNT_DIR" > "$CONFIG_FILE"
        echo -e "${GREEN}[+] Mount folder path saved to $CONFIG_FILE${NC}"
    fi
}

function list_nfs_shares() {
    log "[*] Listing NFS shares for $TARGET_IP"
    showmount -e "$TARGET_IP" 2>/dev/null
}

function mount_nfs_shares() {
    local shares=($(showmount -e "$TARGET_IP" | awk 'NR>1 {print $1}'))
    if [ ${#shares[@]} -eq 0 ]; then
        echo -e "${RED}[!] No NFS shares found on $TARGET_IP${NC}"
        return
    fi

    echo "[*] Found shares:"
    printf '%s\n' "${shares[@]}"

    if $YES_TO_ALL; then
        echo "[*] Proceeding with mounting all shares automatically (--yes-to-all enabled)"
        mount_selected_shares "${shares[@]}"
    else
        read -p "Proceed with mounting all shares to $MOUNT_DIR? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            mount_selected_shares "${shares[@]}"
        else
            echo "[*] Please input specific shares separated by comma:"
            read -p "Example: /data1,/backup  → " input_shares_raw
            IFS=',' read -ra input_shares <<< "$input_shares_raw"

            valid_shares=()
            for input_share in "${input_shares[@]}"; do
                input_share=$(echo "$input_share" | xargs)
                if printf '%s\n' "${shares[@]}" | grep -qx "$input_share"; then
                    valid_shares+=("$input_share")
                else
                    echo -e "${RED}[!] Invalid share: $input_share${NC}"
                fi
            done

            if [ ${#valid_shares[@]} -eq 0 ]; then
                echo -e "${RED}[!] No valid shares selected. Exiting.${NC}"
                exit 1
            fi

            mount_selected_shares "${valid_shares[@]}"
        fi
    fi
}

function mount_selected_shares() {
    mkdir -p "$MOUNT_DIR"

    for share in "$@"; do
        local subdir="${MOUNT_DIR}${share}"
        mkdir -p "$subdir"
        log "[*] Mounting $TARGET_IP:$share to $subdir"
        if sudo mount -t nfs "$TARGET_IP:$share" "$subdir"; then
            echo -e "${GREEN}[+] Mounted $share successfully.${NC}"
        else
            echo -e "${RED}[!] Failed to mount $share.${NC}"
        fi
    done
}

function unmount_nfs_shares() {
    echo "[*] Attempting to unmount everything under $MOUNT_DIR"
    find "$MOUNT_DIR" -type d | while read -r dir; do
        if mountpoint -q "$dir"; then
            log "[*] Unmounting $dir"
            if sudo umount "$dir"; then
                echo -e "${GREEN}[+] Unmounted $dir${NC}"
            else
                echo -e "${RED}[!] Failed to unmount $dir${NC}"
            fi
        fi
    done

    echo "[*] Cleaning up empty mount directories recursively..."
    recursive_cleanup "$MOUNT_DIR"
}

function recursive_cleanup() {
    local path="$1"

    find "$path" -depth -type d | while read -r dir; do
        if [ "$dir" != "$path" ]; then
            if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
                log "[*] Removing empty directory $dir"
                rmdir "$dir" && echo -e "${GREEN}[+] Removed $dir${NC}"
            fi
        fi
    done
}

# Argument Parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i) TARGET_IP="$2"; shift ;;
        --unmount) UNMOUNT=true ;;
        -y|--yes-to-all) YES_TO_ALL=true ;;
        -v) VERBOSE=true ;;
        -h|--help)
            echo "Usage: $0 [-i <target_ip>] [-y] [-v] [--unmount]"
            echo "-i <ip>        Specify target NFS server IP (required for mounting)"
            echo "--unmount      Unmount all shares under saved mount folder"
            echo "-y             Assume yes for all prompts"
            echo "-v             Enable verbose mode"
            exit 0
            ;;
        *) echo -e "${RED}[!] Unknown parameter passed: $1${NC}"; exit 1 ;;
    esac
    shift
done

check_dependencies
load_or_set_mount_dir

if $UNMOUNT; then
    confirm_or_update_mount_dir_unmount
    unmount_nfs_shares
else
    confirm_or_update_mount_dir
    if [ -z "$TARGET_IP" ]; then
        echo -e "${RED}[!] Target IP is required with -i${NC}"
        exit 1
    fi
    list_nfs_shares
    mount_nfs_shares
fi

