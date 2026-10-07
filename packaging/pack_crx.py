"""Packs the browser extension into a CRX3 file, so the build doesn't need Chrome. Stdlib + the openssl CLI.
Usage: pack_crx.py <extension-dir> <rsa-key.pem> <out.crx>"""
import hashlib
import io
import os
import struct
import subprocess
import sys
import zipfile


def varint(n):
    out = b""
    while n > 0x7F:
        out += bytes([n & 0x7F | 0x80])
        n >>= 7
    return out + bytes([n])


def field(number, data):  # protobuf length-delimited field
    return varint(number << 3 | 2) + varint(len(data)) + data


def openssl(*args, data=None):
    return subprocess.run(["openssl", *args], input=data, capture_output=True, check=True).stdout


src, key, out = sys.argv[1:]
zipped = io.BytesIO()
with zipfile.ZipFile(zipped, "w", zipfile.ZIP_DEFLATED) as z:
    for name in sorted(os.listdir(src)):  # top-level files only: skips web-ext-artifacts/ etc.
        if os.path.isfile(os.path.join(src, name)) and not name.startswith("."):
            z.write(os.path.join(src, name), name)
archive = zipped.getvalue()

public_key = openssl("pkey", "-in", key, "-pubout", "-outform", "DER")
signed_data = field(1, hashlib.sha256(public_key).digest()[:16])  # SignedData { crx_id }
signature = openssl("dgst", "-sha256", "-sign", key,
                    data=b"CRX3 SignedData\x00" + struct.pack("<I", len(signed_data)) + signed_data + archive)
# CrxFileHeader { sha256_with_rsa = 2: AsymmetricKeyProof { public_key = 1, signature = 2 }, signed_header_data = 10000 }
header = field(2, field(1, public_key) + field(2, signature)) + field(10000, signed_data)
with open(out, "wb") as f:
    f.write(b"Cr24" + struct.pack("<II", 3, len(header)) + header + archive)
