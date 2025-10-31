# python3 & softlink to uername-anarchy (git clone via github)
#!/usr/bin/env python3

import requests
from bs4 import BeautifulSoup
import re
from urllib.parse import urljoin, urlparse
import sys
import subprocess

# CONFIG
CRAWL_DEPTH = 2

# Regex patterns (expand as needed)
NAME_PATTERN = re.compile(r'\b([A-Z][a-z]+ [A-Z][a-z]+)\b')  # John Doe
USERNAME_PATTERN = re.compile(r'\b([a-zA-Z][\w\.\-_]{2,20})\b')  # jdoe, jane.smith

def crawl(url, visited, depth):
    if depth > CRAWL_DEPTH or url in visited:
        return set()
    print(f'Crawling: {url}')
    visited.add(url)
    try:
        resp = requests.get(url, timeout=5, verify=False)
        soup = BeautifulSoup(resp.text, 'html.parser')
    except Exception as e:
        print(f'Error fetching {url}: {e}')
        return set()

    # Find names/usernames in page text
    text = soup.get_text(separator=' ')
    names = set(NAME_PATTERN.findall(text))
    usernames = set(USERNAME_PATTERN.findall(text))

    found = names | usernames

    # Find more URLs to crawl (same domain, avoid binary links)
    for link in soup.find_all('a', href=True):
        next_url = urljoin(url, link['href'])
        # Stay within the same domain
        if urlparse(next_url).netloc == urlparse(url).netloc:
            if not any(next_url.lower().endswith(x) for x in ('.jpg','.jpeg','.png','.gif','.pdf','.css','.js')):
                found |= crawl(next_url, visited, depth + 1)
    return found

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 web_usernames.py <target_url> [output_file]")
        sys.exit(1)

    target_url = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'found_names.txt'

    # Disable SSL warnings
    requests.packages.urllib3.disable_warnings()

    # Crawl and extract
    found = crawl(target_url, set(), 0)
    found = sorted(set(x.strip() for x in found if len(x.strip()) > 0))

    print(f"\nFound {len(found)} potential names/usernames.")
    with open(output_file, 'w') as f:
        for name in found:
            f.write(name + '\n')
    print(f"Results written to {output_file}")

    # Optional: Chain to username-anarchy if installed
    try:
        print("\n[+] Generating username permutations with username-anarchy...")
        proc = subprocess.run(['username-anarchy', '-i', output_file], capture_output=True, text=True)
        with open('generated_usernames.txt', 'w') as uf:
            uf.write(proc.stdout)
        print(f"Username permutations written to generated_usernames.txt")
    except Exception as e:
        print("username-anarchy not found or failed. You can run it manually:")
        print(f"username-anarchy -i {output_file} > generated_usernames.txt")
