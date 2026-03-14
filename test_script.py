import boto3, requests, time, json, asyncio
from concurrent.futures import ThreadPoolExecutor

# ── FILL THESE IN ──────────────────────────────
USER_POOL_ID     = "us-east-1_feRu9Y3PO"   # from: terraform output in auth/
CLIENT_ID        = "6tp2so5a2k1pjj9nvrjsjnps44"     # from: terraform output in auth/
USERNAME         = "singh.anuragsaurabh@gmail.com"
PASSWORD         = "Satyam123!"   # password you set after first login
API_URL_US       = "https://2hw0ne93if.execute-api.us-east-1.amazonaws.com"   # from envs/us-east-1 output
API_URL_EU       = "https://snzlkibkxl.execute-api.eu-west-1.amazonaws.com"   # from envs/eu-west-1 output
# ───────────────────────────────────────────────

def get_jwt():
    client = boto3.client('cognito-idp', region_name='us-east-1')
    resp = client.initiate_auth(
        AuthFlow='USER_PASSWORD_AUTH',
        AuthParameters={'USERNAME': USERNAME, 'PASSWORD': PASSWORD},
        ClientId=CLIENT_ID
    )
    return resp['AuthenticationResult']['IdToken']

def call_endpoint(url, path, token, label):
    headers = {"Authorization": token}
    start = time.time()
    resp = requests.get(f"{url}{path}", headers=headers)
    latency = round((time.time() - start) * 1000, 2)
    body = resp.json()
    print(f"\n[{label}] Status: {resp.status_code} | Latency: {latency}ms")
    print(f"  Response: {json.dumps(body, indent=2)}")
    if 'region' in body:
        expected = 'us-east-1' if 'us-east' in url else 'eu-west-1'
        match = "✅ PASS" if body['region'] == expected else "❌ FAIL"
        print(f"  Region check: {match} (got '{body['region']}', expected '{expected}')")
    return body

def main():
    print("🔐 Getting JWT from Cognito...")
    token = get_jwt()
    print("✅ JWT obtained\n")

    print("🚀 Calling /greet in both regions concurrently...")
    with ThreadPoolExecutor(max_workers=4) as ex:
        f1 = ex.submit(call_endpoint, API_URL_US, "/greet",    token, "US /greet")
        f2 = ex.submit(call_endpoint, API_URL_EU, "/greet",    token, "EU /greet")
        f3 = ex.submit(call_endpoint, API_URL_US, "/dispatch", token, "US /dispatch")
        f4 = ex.submit(call_endpoint, API_URL_EU, "/dispatch", token, "EU /dispatch")
        for f in [f1, f2, f3, f4]:
            f.result()

    print("\n✅ All calls complete!")

if __name__ == "__main__":
    main()
