#!/usr/bin/env python3
"""Independent WAV checks for the local fixture renders; standard library only."""
from pathlib import Path
import hashlib
import json
import math
import struct
import subprocess
root=Path(__file__).resolve().parents[1]
def read_wav(path):
    data=path.read_bytes()
    assert data[:4]==b'RIFF' and data[8:12]==b'WAVE', 'Expected RIFF WAV'
    chunks={};offset=12
    while offset+8<=len(data):
        tag,size=struct.unpack_from('<4sI',data,offset);offset+=8
        chunks[tag]=data[offset:offset+size];offset+=size+(size%2)
    fmt=chunks[b'fmt '];kind,channels,rate,_,align,bits=struct.unpack_from('<HHIIHH',fmt)
    if kind==65534:kind=struct.unpack_from('<H',fmt,24)[0]
    raw=chunks[b'data'];assert len(raw)%align==0
    if kind==3 and bits==32:values=[v[0] for v in struct.iter_unpack('<f',raw)]
    elif kind==1 and bits in (16,24,32):
        width=bits//8;values=[int.from_bytes(raw[i:i+width],'little',signed=True)/2**(bits-1) for i in range(0,len(raw),width)]
    else:raise AssertionError(f'Unsupported test WAV format {kind}/{bits}')
    assert all(math.isfinite(v) for v in values)
    return (rate,channels,len(raw)//align),values
source=root/'fixtures/local/track-3-vocal-pitch-demo.wav'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='65f7862007194ccf0d75baa9ddb9acf98820247e63758024ac5e143a7b337ece'
metadata,pcm=read_wav(source)
original=root/'build/renders/track-3-original.wav'
assert read_wav(original)==(metadata,pcm), 'No-edit output changes PCM'
for name in ['track-3-note-2-up-2.wav','track-3-note-2-down-2.wav']:
    path=root/'build/renders'/name
    current,samples=read_wav(path)
    assert current==metadata and samples!=pcm
    assert max(map(abs,samples))<1, 'Clipped fixture'
    previous=path.read_bytes()
    attempt=subprocess.run([str(root/'build/pitch-render'),str(source),str(path),'2','2'],capture_output=True)
    assert attempt.returncode!=0 and path.read_bytes()==previous,'Overwrote existing output'
report=json.loads((root/'build/renders/reanalysis-up-2.json').read_text())
shifted=next(n for n in report['notes'] if n['start']<1.4<n['end'])
assert abs(shifted['midi']-59.923349358651016)<.15,'Fixture pitch did not move two semitones'
print('PASS: source hash, decoded PCM bypass, WAV dimensions, finite/unclipped output, overwrite refusal, fixture +2 pitch')
