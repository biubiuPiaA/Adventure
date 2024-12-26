#!/bin/bash
# Used to add into local host DNS Resolve, symlink it to make it easier
# Function to display usage information
usage() {
    echo "Usage: $0 -i <IP_ADDRESS> -d <DOMAIN_NAMES>"
    echo "  -i    IP address to assign"
    echo "  -d    Domain names to map to the IP address (space-separated for multiple domains)"
    exit 1
}

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Parse command-line arguments
while getopts "i:d:" opt; do
    case $opt in
        i) IP_ADDRESS="$OPTARG" ;;
        d) DOMAIN_NAMES="$OPTARG" ;;
        *) usage ;;
    esac
done

# Check if both IP_ADDRESS and DOMAIN_NAMES are provided
if [ -z "$IP_ADDRESS" ] || [ -z "$DOMAIN_NAMES" ]; then
    usage
fi

# Add the IP and domain names to /etc/hosts
echo "Adding the following to /etc/hosts:"
echo "$IP_ADDRESS $DOMAIN_NAMES"

# Backup the original /etc/hosts file
#cp /etc/hosts /etc/hosts.bak

# Append the new entry to /etc/hosts
echo "$IP_ADDRESS $DOMAIN_NAMES" >> /etc/hosts
#printf "%s\t%s\n\n" "$IP" "$DOMAIN_NAMES"| sudo tee -a /etc/hosts
echo "Entry added successfully."

# Display the current contents of /etc/hosts
echo "Current /etc/hosts file:"
cat /etc/hosts
