#!/usr/bin/env python3
"""Build a local Max external and a minimal pass-through M4L probe device."""
from pathlib import Path
import json, plistlib, struct, subprocess

root=Path(__file__).resolve().parents[1]
out=root/'build'
bundle=out/'pitchprobe3.mxo'/'Contents'
(bundle/'MacOS').mkdir(parents=True,exist_ok=True)
(bundle/'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'local.jacob.pitchprobe3', 'CFBundleName':'pitchprobe3',
    'CFBundleExecutable':'pitchprobe3', 'CFBundlePackageType':'BNDL',
    'CFBundleVersion':'1', 'CFBundleShortVersionString':'0.1',
}))
subprocess.run(['xcrun','clang','-bundle','-arch','arm64','-fobjc-arc',
    '-Wno-deprecated-declarations','-Wno-incompatible-pointer-types',
    '-I'+str(root/'vendor/max-sdk-base/c74support/max-includes'),
    '-DPITCH_PROBE_LOG_PATH='+json.dumps(str(root/'probe.log')),
    '-framework','Cocoa','-undefined','dynamic_lookup',
    str(root/'src/pitchprobe.m'),'-o',str(bundle/'MacOS/pitchprobe3')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(bundle.parent)],check=True)
boxes=[]
def box(id, text, rect, cls='newobj', **kw):
    boxes.append({'box':{'id':id,'maxclass':cls,'text':text,'patching_rect':rect,**kw}})
box('in','plugin~',[20,30,70,22])
box('out','plugout~',[20,95,70,22])
box('probe','pitchprobe3',[150,30,100,22])
box('bang','bang',[150,95,50,22], 'message')
box('label','Clip View integration probe — no audio processing',[10,10,340,40],'comment',presentation=1,presentation_rect=[10,10,340,40])
lines=[{'patchline':{'source':[a,n],'destination':[b,m]}} for a,n,b,m in [('in',0,'out',0),('in',1,'out',1),('bang',0,'probe',0)]]
p={'patcher':{'fileversion':1,'appversion':{'major':9,'minor':0,'revision':0,'architecture':'arm64','modernui':1},'rect':[0,0,400,200],'openinpresentation':1,'devicewidth':360,'boxes':boxes,'lines':lines}}
data=json.dumps(p,indent=2).encode()+b'\0'
(out/'Pitch Probe.amxd').write_bytes(b'ampf'+struct.pack('<I',4)+b'aaaa'+b'meta'+struct.pack('<II',4,0)+b'ptch'+struct.pack('<I',len(data))+data)
print(out/'Pitch Probe.amxd')
