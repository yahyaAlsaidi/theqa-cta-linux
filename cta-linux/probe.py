"""Calls the CTA SmartCardHub like the IdP page does and prints each result, so the Linux host can be
diffed against the Windows CTA (under Wine). Run: ../.venv/bin/python probe.py [--pin] [http://localhost:5234]
--pin also logs in and signs a random challenge; it asks for the PIN on the terminal. A wrong PIN uses up a card attempt."""
import asyncio
import base64
import getpass
import json
import os
import struct
import sys
import uuid

from aiohttp import ClientSession

ARGS = [a for a in sys.argv[1:] if a != "--pin"]
BASE = ARGS[0] if ARGS else "http://localhost:5234"
ORIGIN = {"Origin": "https://idp-pki.mtcit.gov.om"}
CALLS = [("GetCtaAppVersionAsync", None), ("InitAsync", None), ("IsDeviceConnectedAsync", None),
         ("GetCardInfoAsync", None), ("GetCertificatesAsync", 1)]
if "--pin" in sys.argv:
    CALLS += [("LogInAndVerifyPinAsync", getpass.getpass("Card PIN: ")),
              ("SignDataAsync", {"CertificateType": 1, "Data": base64.b64encode(os.urandom(32)).decode()}),
              ("LogoutAsync", None)]


def shape(result):
    """[WrapAndEncrypt] results are b64(len || RSA-OAEP(aes key) || nonce12 || tag16 || ciphertext); show the layout, not the bytes."""
    try:
        raw = base64.b64decode(result, validate=True)
        n = struct.unpack(">i", raw[:4])[0]
        if len(raw) > 4 + n + 28:
            return f"<encrypted: rsa {n}B, ciphertext {len(raw) - 4 - n - 28}B>"
    except (TypeError, ValueError, struct.error):
        pass
    return result


async def main():
    async with ClientSession() as http:
        evil = await http.post(f"{BASE}/SmartCardHub/negotiate?negotiateVersion=1", headers={"Origin": "https://evil.example"})
        print("foreign origin negotiate:", evil.status)
        r = await http.post(f"{BASE}/SmartCardHub/negotiate?negotiateVersion=1", headers=ORIGIN)
        token = (await r.json())["connectionToken"]
        async with http.ws_connect(f"{BASE.replace('http', 'ws')}/SmartCardHub?id={token}", headers=ORIGIN) as ws:
            await ws.send_str('{"protocol":"json","version":1}\x1e')
            await ws.receive_str()
            for i, (target, payload) in enumerate(CALLS):
                await ws.send_str(json.dumps({"type": 1, "invocationId": str(i), "target": target,
                                              "arguments": [{"id": str(uuid.uuid4()), "payload": payload}]}) + "\x1e")
                while True:
                    for frame in filter(None, (await ws.receive_str(timeout=30)).split("\x1e")):
                        m = json.loads(frame)
                        if m.get("type") == 1:  # server event (ErrorOccurred, SmartCardDetected, ...)
                            print(f"  event {m['target']}: {json.dumps(m['arguments'])[:160]}")
                        elif m.get("type") == 3:
                            print(f"{target}: {shape(m.get('result')) if 'result' in m else 'ERROR ' + m.get('error', '')}")
                            break
                    else:
                        continue
                    break


asyncio.run(main())
