#!/bin/bash

# Description: Clean Kali Linux storage (logs > 3 days, orphaned packages, etc.)
# Author: ChatGPT x ask_pentest
# Date: $(date)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🧹 Starting Kali Cleanup Script...${NC}"

echo -e "${GREEN}\n📦 Disk Usage Before:${NC}"
df -h /

# 1. Clean log files older than 3 days
echo -e "${GREEN}\n🗑️ Cleaning log files older than 3 days...${NC}"
sudo find /var/log -type f -name "*.log" -mtime +3 -exec rm -f {} \;

# 2. Clear APT cache
echo -e "${GREEN}\n📦 Cleaning APT cache...${NC}"
sudo apt clean
sudo apt autoclean

# 3. Remove unused packages
echo -e "${GREEN}\n🧯 Removing unused/orphaned packages...${NC}"
sudo apt autoremove -y

# 4. Clean journald logs (if using systemd-journald)
if command -v journalctl &> /dev/null; then
    echo -e "${GREEN}\n📚 Vacuuming systemd journal logs (older than 3 days)...${NC}"
    sudo journalctl --vacuum-time=3d
fi

# 5. Clear thumbnail cache
echo -e "${GREEN}\n🖼️ Cleaning thumbnail cache...${NC}"
rm -rf ~/.cache/thumbnails/*

# 6. Empty Trash
echo -e "${GREEN}\n🗑️ Emptying user trash...${NC}"
rm -rf ~/.local/share/Trash/files/*
rm -rf ~/.local/share/Trash/info/*

# 7. Clear Bash history (optional - uncomment if needed)
# echo -e "${GREEN}\n📜 Clearing Bash history...${NC}"
# history -c && history -w

# 8. Show final usage
echo -e "${GREEN}\n✅ Cleanup complete.${NC}"
echo -e "${GREEN}\n💽 Disk Usage After:${NC}"
df -h /
