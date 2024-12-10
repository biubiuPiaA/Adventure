#!/bin/bash

#**Not complete yet, user need to have kerbrute as well, current status only for the smb port and ldap port detection***
# Prompt for IP address
read -p "Enter the target IP address: " target_ip

# Run nmap scan
echo "Running nmap scan on $target_ip..."
nmap -Pn -p- -sVC "$target_ip" -oN nmap_result.txt

# Check for SMB port (445) in the nmap result
if grep -q "445/tcp.*open.*microsoft-ds" nmap_result.txt; then
    echo "SMB port is open. Running smbclient..."
    smbclient -L //$target_ip/
else
    echo "SMB port is not open."
fi

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
