#!/usr/bin/env python3
"""Build the interim Max for Live device; no native Clip View hooks."""
from pathlib import Path
import json
import plistlib
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / 'build'
external = 'pitchclip2'
contents = out / (external+'.mxo') / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.jacob.'+external, 'CFBundleName': external,
    'CFBundleExecutable': external, 'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1',
}))
subprocess.run(['xcrun', 'clang++', '-std=c++17', '-O2', '-bundle', '-arch', 'arm64', '-fobjc-arc',
    '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-cast-function-type-mismatch',
    '-DPITCHCLIP_CLASS='+json.dumps(external),
    '-I'+str(root/'vendor/max-sdk-base/c74support/max-includes'),
    '-framework', 'AVFoundation', '-framework', 'Foundation', '-undefined', 'dynamic_lookup',
    str(root/'src/pitch_clip.mm'), str(root/'src/pitch_core.cpp'),
    '-o', str(contents/'MacOS'/external)], check=True)
subprocess.run(['codesign','--force','--sign','-',str(contents.parent)],check=True)
boxes=[]
def box(id, text, rect, cls='newobj', **kw):
    boxes.append({'box':{'id':id,'maxclass':cls,'text':text,'patching_rect':rect,**kw}})
box('in','plugin~',[10,220,70,22])
box('out','plugout~',[10,260,70,22])
box('editor','',[0,0,700,160],cls=external,presentation=1,presentation_rect=[0,0,700,160])
box('pathmsg','path live_set view detail_clip',[100,190,200,22],cls='message')
box('path','live.path',[100,220,80,22])
box('order','t b l',[100,250,60,22])
box('get','get file_path',[100,280,90,22],cls='message')
box('object','live.object',[260,280,80,22])
box('route','route file_path',[260,310,100,22])
box('read','prepend read',[260,340,100,22])
connections=[('in',0,'out',0),('in',1,'out',1),('editor',0,'pathmsg',0),
    ('pathmsg',0,'path',0),('path',0,'order',0),('order',1,'object',1),
    ('order',0,'get',0),('get',0,'object',0),('object',0,'route',0),('route',0,'read',0),('read',0,'editor',0)]
p={'patcher':{'fileversion':1,'appversion':{'major':9,'minor':0,'revision':0,'architecture':'arm64','modernui':1},
    'rect':[0,0,740,400],'openinpresentation':1,'devicewidth':700,'boxes':boxes,
    'lines':[{'patchline':{'source':[a,n],'destination':[b,m]}} for a,n,b,m in connections]}}
data=json.dumps(p,indent=2).encode()+b'\0'
device=out/'Pitch Editor.amxd'
device.write_bytes(b'ampf'+struct.pack('<I',4)+b'aaaa'+b'meta'+struct.pack('<II',4,0)+b'ptch'+struct.pack('<I',len(data))+data)
print(device)
