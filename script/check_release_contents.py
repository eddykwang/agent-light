"""Reject private signing material before upload and after final extraction."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
for path in root.rglob('*'):
    if not path.is_file():
        continue
    if path.suffix.lower() in {'.p12', '.pfx', '.p8', '.pem', '.key', '.keychain', '.keychain-db'}:
        sys.exit(f"Unexpected signing material in app: {path.relative_to(root)}")
    data = path.read_bytes()
    if any(marker in data for marker in (
        b'-----BEGIN PRIVATE KEY-----', b'-----BEGIN ENCRYPTED PRIVATE KEY-----',
        b'-----BEGIN RSA PRIVATE KEY-----', b'-----BEGIN EC PRIVATE KEY-----',
        b'-----BEGIN OPENSSH PRIVATE KEY-----',
    )):
        sys.exit(f"Private key found in app: {path.relative_to(root)}")
