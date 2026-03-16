import requests

api_endpoints = [
    "https://taskearn-production-production.up.railway.app/api",
    "http://localhost:5000/api",
    "https://your-railway-url.up.railway.app/api",
    "https://web-production-b8388.up.railway.app/api"
]

import datetime
def check_api_connectivity(endpoints):
    log_file = "api_connectivity_log.txt"
    now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    results = []
    for url in endpoints:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                msg = f"[OK] {url} is connected."
            else:
                msg = f"[WARN] {url} returned status {response.status_code}."
        except requests.RequestException as e:
            msg = f"[FAIL] {url} is not connected. Error: {e}"
        print(msg)
        results.append(f"{now} {msg}")
    with open(log_file, "a") as f:
        f.write("\n".join(results) + "\n")

if __name__ == "__main__":
    check_api_connectivity(api_endpoints)
