#!/usr/bin/env python3
"""Build a local Max external and a minimal pass-through M4L probe device."""
from pathlib import Path
import json, plistlib, struct, subprocess

root=Path(__file__).resolve().parents[1]
import hashlib
expected='fca7d75481af0b561a51fdece48bc1fbd50c0e2c6ad04f34c6f794173be75d47'
assert hashlib.sha256((root/'build/Ableton Pitch Lab.app/Contents/MacOS/Live').read_bytes()).hexdigest()==expected, 'Unsupported experimental executable'

out=root/'build'
bundle=out/'pitchmount1.mxo'/'Contents'
(bundle/'MacOS').mkdir(parents=True,exist_ok=True)
(bundle/'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'local.jacob.pitchmount1', 'CFBundleName':'pitchmount1',
    'CFBundleExecutable':'pitchmount1', 'CFBundlePackageType':'BNDL',
    'CFBundleVersion':'1', 'CFBundleShortVersionString':'0.1',
}))
subprocess.run(['xcrun','clang++','-bundle','-arch','arm64','-fobjc-arc',
    '-Wno-deprecated-declarations','-Wno-incompatible-pointer-types',
    '-I'+str(root/'vendor/max-sdk-base/c74support/max-includes'),
    '-DPITCH_MOUNT_LOG='+json.dumps(str(root/'mount.log')),
    '-DPITCH_LIVE_COPY='+json.dumps(str(root/'build/Ableton Pitch Lab.app')),
    '-framework','Cocoa','-framework','QuartzCore','-undefined','dynamic_lookup',
    str(root/'src/pitch_mount.mm'),str(root/'src/native_factory_arm64.S'),'-o',str(bundle/'MacOS/pitchmount1')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(bundle.parent)],check=True)
boxes=[]
def box(id, text, rect, cls='newobj', **kw):
    boxes.append({'box':{'id':id,'maxclass':cls,'text':text,'patching_rect':rect,**kw}})
box('in','plugin~',[20,30,70,22])
box('out','plugout~',[20,95,70,22])
box('probe','pitchmount1',[150,30,100,22])
box('bang','bang',[150,95,50,22], 'message')
box('label','Native host attachment test — removes itself after 20 seconds',[10,10,340,40],'comment',presentation=1,presentation_rect=[10,10,340,40])
lines=[{'patchline':{'source':[a,n],'destination':[b,m]}} for a,n,b,m in [('in',0,'out',0),('in',1,'out',1),('bang',0,'probe',0)]]
p={'patcher':{'fileversion':1,'appversion':{'major':9,'minor':0,'revision':0,'architecture':'arm64','modernui':1},'rect':[0,0,400,200],'openinpresentation':1,'devicewidth':360,'boxes':boxes,'lines':lines}}
data=json.dumps(p,indent=2).encode()+b'\0'
(out/'Pitch Mount Test.amxd').write_bytes(b'ampf'+struct.pack('<I',4)+b'aaaa'+b'meta'+struct.pack('<II',4,0)+b'ptch'+struct.pack('<I',len(data))+data)
print(out/'Pitch Mount Test.amxd')
