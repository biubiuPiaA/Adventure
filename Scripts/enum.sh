#!/bin/bash

# Protocol & Service that done → SMB, LDAP, NFS
# Prompt for IP address
read -p "Enter the target IP address: " target_ip

# Run nmap scan
echo "Running nmap scan on $target_ip..."
nmap -Pn -sVC "$target_ip" -oN nmap_result.txt
echo ""

# Check for SMB port (445) in the nmap result
echo "== SMB ======================================================================================================"
echo ""
if grep -q "445/tcp.*open.*microsoft-ds" nmap_result.txt; then
    echo "SMB port is open. Running smbclient..."
    smbclient -L //$target_ip/
    
else
    echo "SMB port is not open."
fi
echo ""

echo "== LDAP ====================================================================================================="
echo ""
# Check for LDAP port (389 or 3268) in the nmap result
if grep -q -E "389/tcp.*open.*ldap|3268/tcp.*open.*ldap" nmap_result.txt; then
    echo "LDAP port is open. Running ldapsearch..."

    # Extract the domain components (DC) from DNS_Domain_Name
    dns_domain=$(grep "DNS_Domain_Name:" nmap_result.txt | awk -F 'DNS_Domain_Name:' '{print $2}' | awk '{$1=$1; print}')
    if [[ -n $dns_domain ]]; then
        dc_string=$(echo "$dns_domain" | awk -F '.' '{
            for (i=1; i<=NF; i++) {
                printf "DC=%s,", $i;
            }
        }' | sed 's/,$//')

        # Run ldapsearch with the extracted domain components
        # ldapsearch -x -H ldap://$target_ip -D '' -w '' -b "$dc_string" | grep sAMAccountName | awk -F: '{ print $2 }' | awk '{ gsub(/ /,""); print }' > user.txt
	ldapsearch -x -H ldap://$target_ip -D '' -w '' -b "$dc_string" > ldap.txt

	#extract keyword from ldap.txt
	cat ldap.txt | grep -E 'password|description' > keyword.txt
	
	# Parse and extract valid usernames
	grep "^# " "ldap.txt" | awk -F ', ' '
	{
    		# Process only if the line has multiple parts (to avoid invalid entries)
		if (NF > 1) {
		        name = $1;                 # Extract the first field (e.g., "# Ian Walker")
		        sub("# ", "", name);       # Remove the leading "# "
		        gsub(" ", ".", name);      # Replace spaces with dots
		        print name;                # Print the result
		}
	}' > "user.txt"

	# Check if any usernames were extracted
	if [[ -s "user.txt" ]]; then
		echo "Usernames extracted and saved to user.txt."
		
		# Extract short domain (first part of DNS domain)
		short_domain=$(echo "$dns_domain" | awk -F '.' '{print $1}')
		
		# Run kerbrute with the extracted domain
	        echo "Running kerbrute user enumeration..."
        	kerbrute userenum -d "$dns_domain" --dc "$target_ip" user.txt -v
	else
	    echo "No valid usernames found in user.txt."
	fi  
       
    else
        echo "Failed to extract LDAP domain components from DNS_Domain_Name."
    fi
else
    echo "LDAP port is not open."
fi
echo ""

echo "== NFS ======================================================================================================="
echo ""
# Check for NFS port (2049) in the nmap result
if grep -q "2049/tcp.*open" nmap_result.txt; then
    echo "NFS port is open. Extracting NFS details..."

    # Extract NFS version
    nfs_version=$(grep "2049/tcp.*nfs" nmap_result.txt | grep -Eo "[0-9]+-[0-9]+")
    if [[ -n $nfs_version ]]; then
        smallest_version=$(echo "$nfs_version" | awk -F '-' '{print $1}')
        echo "NFS Version detected: $nfs_version (Smallest: $smallest_version)"
    else
        echo "NFS Version could not be determined. Using default version 3."
        smallest_version=3
    fi

    # List available NFS shares on the target IP
    echo "Fetching available NFS shares from $target_ip..."
    available_shares=$(showmount -e "$target_ip" 2>/dev/null | grep -v "Export list" | awk '{print $1}')

    if [[ -z "$available_shares" ]]; then
        echo "No NFS shares found on $target_ip. Exiting."
        exit 1
    fi

    echo "The following NFS shares are available:"
    echo "$available_shares"

    # Prompt user for the local mount base directory
    read -p "Enter the local base directory name for mounting: " base_dir

    # Define the full local mount directory path
    local_mount_base="/home/kali/all/mnt/$base_dir/"

    # Check if the base directory exists, if not create it
    if [[ ! -d "$local_mount_base" ]]; then
        echo "Directory $local_mount_base does not exist. Creating it..."
        mkdir -p "$local_mount_base"
        echo "Directory created at $local_mount_base"
    fi

    # Loop through each NFS share and mount it
    for share in $available_shares; do
        # Create a subdirectory for each share
        mount_point="$local_mount_base$(echo "$share" | tr '/' '_')"
        mkdir -p "$mount_point"

        # Mount the NFS share
        echo "Mounting $share to $mount_point..."
        sudo mount -t nfs -o vers="$smallest_version",nolock "$target_ip:$share" "$mount_point"

        # Verify if the mount was successful
        if mount | grep -q "$mount_point"; then
            echo "Mounted $share successfully at $mount_point."
        else
            echo "Failed to mount $share."
        fi
    done

    echo "All available NFS shares have been mounted under $local_mount_base."
else
    echo "NFS port is not open."
fi
echo ""
