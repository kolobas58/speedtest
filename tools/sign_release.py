"""Подписывает релиз: создаёт latest.json для Speedtest.exe.

Использование:
    UPDATE_SIGNING_KEY=<hex 32 байта> python tools/sign_release.py dist/Speedtest-Portable.exe 1.2.0 > dist/latest.json
    python tools/sign_release.py --keygen      # новая пара ключей (один раз)
"""
import hashlib
import json
import os
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def raw_pub(key):
    return key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()


if len(sys.argv) > 1 and sys.argv[1] == "--keygen":
    k = Ed25519PrivateKey.generate()
    priv = k.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                           serialization.NoEncryption()).hex()
    print(json.dumps({"private": priv, "public": raw_pub(k)}, indent=2))
    sys.exit(0)

exe, version = sys.argv[1], sys.argv[2]
key = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(os.environ["UPDATE_SIGNING_KEY"].strip()))
data = open(exe, "rb").read()
name = os.path.basename(exe)
digest = hashlib.sha256(data).hexdigest()
msg = f"{version}|{name}|{digest}|{len(data)}".encode()
print(json.dumps({"version": version, "file": name, "sha256": digest, "size": len(data),
                  "sig": key.sign(msg).hex(), "pub": raw_pub(key)}, indent=2))
