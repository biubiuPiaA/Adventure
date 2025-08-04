#check the subdomain alive or not with nmap -Pn -p80,443 → -Pn → -Pn -p- 
# ./subdomain_alive.sh subdomain.txt
#!/bin/bash

# Usage: ./domain_scan.sh subdomains.txt
# Input file: one domain/subdomain per line

INPUT_FILE="$1"
MAIN_OUTPUT="scan_results.txt"
NO_PORTS_OUTPUT="no_open_ports.txt"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file not found!"
  echo "Usage: $0 subdomains.txt"
  exit 1
fi

# Clear previous outputs
> "$MAIN_OUTPUT"
> "$NO_PORTS_OUTPUT"

TOTAL=0
WITH_PORTS=0
WITHOUT_PORTS=0

echo "🚀 Starting scan for domains listed in $INPUT_FILE ..."
echo "Results will be saved to $MAIN_OUTPUT"
echo "Domains with no open ports will be saved to $NO_PORTS_OUTPUT"
echo "============================================================="

while read -r domain; do
  [[ -z "$domain" ]] && continue # Skip empty lines
  TOTAL=$((TOTAL+1))
  echo "🔍 Scanning $domain (step 1: ports 80,443)..."

  # Step 1: Check ports 80,443
  SCAN_RESULT=$(nmap -Pn -p80,443 "$domain")
  OPEN_PORTS=$(echo "$SCAN_RESULT" | grep -i "open")

  if [[ -z "$OPEN_PORTS" ]]; then
    echo "❗ No open ports on 80,443. Running full scan (-p-)..."
    SCAN_RESULT=$(nmap -Pn -p- "$domain")
    OPEN_PORTS=$(echo "$SCAN_RESULT" | grep -i "open")
  fi

  echo -e "\n================== Scan Result for $domain ==================\n" >> "$MAIN_OUTPUT"
  echo "$SCAN_RESULT" >> "$MAIN_OUTPUT"
  echo -e "\n=============================================================\n" >> "$MAIN_OUTPUT"

  if [[ -z "$OPEN_PORTS" ]]; then
    echo "❌ $domain has NO open ports"
    echo "$domain" >> "$NO_PORTS_OUTPUT"
    WITHOUT_PORTS=$((WITHOUT_PORTS+1))
  else
    echo "✅ $domain has open ports"
    WITH_PORTS=$((WITH_PORTS+1))
  fi

done < "$INPUT_FILE"

# Final summary
echo "============================================================="
echo "✅ Scan completed!"
echo "Total subdomains scanned: $TOTAL"
echo "Subdomains with open ports: $WITH_PORTS"
echo "Subdomains with NO open ports: $WITHOUT_PORTS"
echo "Results saved to: $MAIN_OUTPUT"
echo "No open ports saved to: $NO_PORTS_OUTPUT"

# Append summary to output file
{
  echo -e "\n===================== SCAN SUMMARY ====================="
  echo "Total subdomains scanned: $TOTAL"
  echo "Subdomains with open ports: $WITH_PORTS"
  echo "Subdomains with NO open ports: $WITHOUT_PORTS"
  echo "Results saved to: $MAIN_OUTPUT"
  echo "No open ports saved to: $NO_PORTS_OUTPUT"
  echo "========================================================"
} >> "$MAIN_OUTPUT"
