#!/usr/bin/env python3
"""Fetch the unmodified, pinned GPL dependency for local evaluation only."""
from pathlib import Path
import hashlib
import io
import tarfile
import urllib.request
root=Path(__file__).resolve().parents[1]
url='https://breakfastquay.com/files/releases/rubberband-4.0.0.tar.bz2'
expected='af050313ee63bc18b35b2e064e5dce05b276aaf6d1aa2b8a82ced1fe2f8028e9'
data=urllib.request.urlopen(url,timeout=60).read()
if hashlib.sha256(data).hexdigest()!=expected:raise SystemExit('Dependency checksum mismatch')
(root/'vendor').mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(data),mode='r:bz2') as archive:
    archive.extractall(root/'vendor',filter='data')
print('Rubber Band 4.0.0 source installed in vendor/. See its COPYING before redistribution.')
