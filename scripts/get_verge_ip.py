#!/usr/bin/env python3
import argparse
import json
import os
import sys
import requests
import urllib3

# Suppress InsecureRequestWarning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def get_env_var(var_name, default=None):
    val = os.environ.get(var_name, default)
    if val is None:
        # Try reading from files if not in env
        if var_name == "VERGEOS_TOKEN" and os.path.exists("/home/adminuser/.vergeos-token"):
             with open("/home/adminuser/.vergeos-token", "r") as f:
                 return f.read().strip()
        if var_name == "VERGEOS_PASS" and os.path.exists("/home/adminuser/.vergeos-credentials"):
             # naive parsing
             with open("/home/adminuser/.vergeos-credentials", "r") as f:
                 for line in f:
                     if "VERGEOS_PASS" in line:
                         return line.split('"')[1]
        
    return val

VERGE_HOST = get_env_var("VERGEOS_HOST", "192.168.1.111")
VERGE_USER = get_env_var("VERGEOS_USER")
VERGE_PASS = get_env_var("VERGEOS_PASS")

def api_request(method, endpoint, token=None, data=None, params=None):
    url = f"https://{VERGE_HOST}/api{endpoint}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["x-yottabyte-token"] = token
    
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, params=params, verify=False, data=json.dumps(data) if data else None)

        elif method == "POST":
            response = requests.post(url, headers=headers, json=data, verify=False)
        
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error: {e}")
        if e.response is not None:
             print(f"Response: {e.response.text}")
        sys.exit(1)

def get_token():
    # Try existing token first
    token = get_env_var("VERGEOS_TOKEN")
    if token:
        # Verify it works? For now assume yes, if fail we could retry logic but keep it simple
        return token
        
    # Authenticate
    print("Authenticating...", file=sys.stderr)
    data = {
        "login": VERGE_USER,
        "password": VERGE_PASS
    }
    # Note: Using /sys/tokens as discovered
    # However, api_request adds /api base. User used /sys/tokens directly on root?
    # User command: verge-cli ... /sys/tokens
    # Base URL in cli script was /api/v4, but user used /sys/tokens. 
    # Let's try raw URL construction for auth
    url = f"https://{VERGE_HOST}/api/sys/tokens" # It is usually under /api/sys/tokens or just /sys/tokens?
    # CLI help says "Make an api call to the appserver"
    # CLI default API info says ... nothing specific about prefix for passed path.
    # The user passed /sys/tokens. 
    # Let's try https://HOST/api/sys/tokens
    
    try:
        resp = requests.post(f"https://{VERGE_HOST}/api/sys/tokens", json=data, verify=False)
        resp.raise_for_status()
        return resp.json().get("$key")
    except Exception:
        # Try without /api
        resp = requests.post(f"https://{VERGE_HOST}/sys/tokens", json=data, verify=False)
        resp.raise_for_status()
        return resp.json().get("$key")

import time

# ... (imports)

def main():
    parser = argparse.ArgumentParser(description="Get VergeOS VM IP Address")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--machine-id", type=int, help="Machine ID (e.g. 93)")
    group.add_argument("--machine-name", type=str, help="Machine Name (e.g. talos-cp-01)")
    parser.add_argument("--timeout", type=int, default=0, help="Wait timeout in seconds (default: 0 = no wait)")
    
    args = parser.parse_args()
    
    token = get_token()
    
    args = parser.parse_args()
    
    token = get_token()
    
    # Resolve Name to ID once (ID shouldn't change)
    machine_id = args.machine_id
    if args.machine_name:
        params = {"filter": f"name eq '{args.machine_name}'"}
        vms = api_request("GET", "/v4/vms", token=token, params=params)
        if not vms:
            print(f"Machine '{args.machine_name}' not found.", file=sys.stderr)
            sys.exit(1)
        machine_id = vms[0]['machine']
        print(f"Resolved '{args.machine_name}' to Machine ID: {machine_id}", file=sys.stderr)

    # Retry loop
    api_url = f"https://{VERGE_HOST}/api/v4"
    start_time = time.time()
    
    while True:
        # Get NICs
        params = {
            "filter": f"machine eq {machine_id}",
            "fields": "macaddress,$key"
        }
        nics = api_request("GET", "/v4/machine_nics", token=token, params=params)
        
        found_ips = []
        if nics:
            for nic in nics:
                mac = nic.get('macaddress')
                if not mac:
                    continue
                
                # Lookup IP by MAC
                params = {"filter": f"mac eq '{mac}'"}
                addrs = api_request("GET", "/v4/vnet_addresses", token=token, params=params)
                
                for addr in addrs:
                    ip = addr.get('ip')
                    if ip:
                        found_ips.append(ip)
                        print(ip) # Output to stdout

        if found_ips:
            sys.exit(0)
            
        if args.timeout <= 0:
            break
            
        elapsed = time.time() - start_time
        if elapsed > args.timeout:
            print(f"Timeout waiting for IP after {args.timeout}s", file=sys.stderr)
            sys.exit(1)
            
        print(f"Waiting for IP... ({int(elapsed)}/{args.timeout}s)", file=sys.stderr)
        time.sleep(5)

    if not found_ips:
        print("No IP addresses found.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
