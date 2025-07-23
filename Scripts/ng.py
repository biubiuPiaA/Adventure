# python3 ng.py -p port_no
#!/usr/bin/env python3
import argparse
import subprocess
import signal
import sys
import os
import requests
import time
import shutil

def start_python_server(port):
    return subprocess.Popen(
        ["python3", "-m", "http.server", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

def start_ngrok(port):
    return subprocess.Popen(
        ["ngrok", "http", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

def get_ngrok_url(retries=10, delay=1):
    """Fetch public ngrok tunnel URL from local API"""
    for _ in range(retries):
        try:
            resp = requests.get("http://127.0.0.1:4040/api/tunnels")
            tunnels = resp.json().get("tunnels", [])
            for tunnel in tunnels:
                if tunnel["proto"] == "https":
                    return tunnel["public_url"]
        except requests.exceptions.ConnectionError:
            time.sleep(delay)
    return None

def check_ngrok_installed():
    if shutil.which("ngrok") is None:
        print("[!] ngrok not found in PATH. Please install ngrok: https://ngrok.com/download")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Start local Python server with ngrok tunnel.")
    parser.add_argument('-p', '--port', type=int, default=8000, help='Port to serve on')
    args = parser.parse_args()
    port = args.port

    check_ngrok_installed()

    print(f"[+] Starting Python HTTP server on port {port}...")
    server_proc = start_python_server(port)

    print("[+] Starting ngrok tunnel...")
    ngrok_proc = start_ngrok(port)

    print("[*] Waiting for ngrok to initialize...")
    ngrok_url = get_ngrok_url()
    if ngrok_url:
        print(f"[🌐] Public ngrok URL: {ngrok_url}")
    else:
        print("[!] Could not retrieve ngrok URL. Is ngrok running?")
        server_proc.terminate()
        ngrok_proc.terminate()
        sys.exit(1)

    print("[✔] Server is live. Press Ctrl+C to stop.")

    try:
        signal.pause()
    except KeyboardInterrupt:
        print("\n[!] Shutting down...")

        print("[x] Stopping ngrok...")
        ngrok_proc.terminate()
        ngrok_proc.wait()

        print("[x] Stopping Python server...")
        server_proc.terminate()
        server_proc.wait()

        print("[✔] Clean exit.")

if __name__ == "__main__":
    main()
