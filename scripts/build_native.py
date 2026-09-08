#!/usr/bin/env python3
"""Build the experimental native Clip View adapter and its Max loader."""
from pathlib import Path
import json
import plistlib
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / 'build'
external = 'pitchnative20'
import hashlib
assert hashlib.sha256((root/'build/Ableton Pitch Lab.app/Contents/MacOS/Live').read_bytes()).hexdigest() == 'fca7d75481af0b561a51fdece48bc1fbd50c0e2c6ad04f34c6f794173be75d47', 'Unsupported executable'
contents = out / (external+'.mxo') / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.jacob.'+external, 'CFBundleName': external,
    'CFBundleExecutable': external, 'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1',
}))
subprocess.run(['xcrun', 'clang++', '-std=c++17', '-O2', '-bundle', '-arch', 'arm64', '-fobjc-arc',
    '-DPitchCanvas=PitchCanvas20', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-cast-function-type-mismatch',
    '-DPITCH_NATIVE_LOG='+json.dumps(str(root/'native.log')),
    '-DPITCH_LIVE_COPY='+json.dumps(str(root/'build/Ableton Pitch Lab.app')),
    '-I'+str(root/'vendor/max-sdk-base/c74support/max-includes'),
    '-framework', 'AVFoundation', '-framework', 'Cocoa', '-framework', 'CoreText', '-undefined', 'dynamic_lookup',
    str(root/'src/pitch_native.mm'), str(root/'src/pitch_core.cpp'), str(root/'src/pitch_canvas.mm'), str(root/'src/native_factory_arm64.S'),
    '-o', str(contents/'MacOS'/external)], check=True)
subprocess.run(['codesign','--force','--sign','-',str(contents.parent)],check=True)
boxes=[]
def box(id, text, rect, cls='newobj', **kw):
    boxes.append({'box':{'id':id,'maxclass':cls,'text':text,'patching_rect':rect,**kw}})
box('in','plugin~',[10,220,70,22])
box('out','plugout~',[10,260,70,22])
box('editor',external,[10,10,120,22])
box('label','Pitch Editor is in the audio clip header',[10,10,310,40],cls='comment',presentation=1,presentation_rect=[10,10,310,40])
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
box('playpathmsg','path live_set view detail_clip',[400,190,200,22],cls='message')
box('playpath','live.path',[400,220,80,22])
box('playorder','t b l',[400,250,60,22])
box('playget','get warping, get warp_markers, get is_arrangement_clip, get start_time, get end_time, get start_marker, get loop_start, get loop_end, get looping, get muted, get is_playing, get playing_position',[400,280,350,22],cls='message')
box('playobject','live.object',[400,310,90,22])
box('playroute','route warping warp_markers is_playing playing_position is_arrangement_clip start_time end_time start_marker loop_start loop_end looping muted',[400,340,350,22])
for i,cmd in enumerate(['warping','warpmap','playing','position']):
    box('play'+cmd,'prepend '+cmd,[400,380+i*30,130,22])
    connections += [('playroute',i,'play'+cmd,0),('play'+cmd,0,'editor',0)]
connections += [('pollorder',0,'playpathmsg',0),('playpathmsg',0,'playpath',0),('playpath',0,'playorder',0),('playorder',1,'playobject',1),('playorder',0,'playget',0),('playget',0,'playobject',0),('playobject',0,'playroute',0)]
for i,prop in enumerate(['is_arrangement_clip','start_time','end_time','start_marker','loop_start','loop_end','looping','muted']):
    box('meta'+prop,'prepend state '+prop,[600,400+i*24,200,22])
    connections += [('playroute',4+i,'meta'+prop,0),('meta'+prop,0,'editor',0)]
box('pollorder','t b b b',[600,10,60,22])
box('songpathmsg','path live_set',[600,40,100,22],cls='message')
box('songpath','live.path',[600,70,80,22])
box('songorder','t b l',[600,100,60,22])
box('songget','get is_playing, get current_song_time',[600,130,200,22],cls='message')
box('songobject','live.object',[600,160,80,22])
box('songroute','route is_playing current_song_time',[600,190,200,22])
box('songplaying','prepend state songplaying',[600,220,180,22])
box('songtime','prepend state songtime',[600,250,180,22])
connections += [('editor',1,'pollorder',0),('pollorder',1,'songpathmsg',0),('songpathmsg',0,'songpath',0),('songpath',0,'songorder',0),('songorder',1,'songobject',1),('songorder',0,'songget',0),('songget',0,'songobject',0),('songobject',0,'songroute',0),('songroute',0,'songplaying',0),('songroute',1,'songtime',0),('songplaying',0,'editor',0),('songtime',0,'editor',0)]
box('viewpathmsg','path live_set view',[850,40,130,22],cls='message')
box('viewpath','live.path',[850,70,80,22])
box('vieworder','t b l',[850,100,60,22])
box('viewget','get follow_song',[850,130,120,22],cls='message')
box('viewobject','live.object',[850,160,80,22])
box('viewroute','route follow_song',[850,190,130,22])
box('viewfollow','prepend state follow',[850,220,150,22])
connections += [('pollorder',2,'viewpathmsg',0),('viewpathmsg',0,'viewpath',0),('viewpath',0,'vieworder',0),('vieworder',1,'viewobject',1),('vieworder',0,'viewget',0),('viewget',0,'viewobject',0),('viewobject',0,'viewroute',0),('viewroute',0,'viewfollow',0),('viewfollow',0,'editor',0)]
p={'patcher':{'fileversion':1,'appversion':{'major':9,'minor':0,'revision':0,'architecture':'arm64','modernui':1},
    'rect':[0,0,740,400],'openinpresentation':1,'devicewidth':330,'boxes':boxes,
    'lines':[{'patchline':{'source':[a,n],'destination':[b,m]}} for a,n,b,m in connections]}}
data=json.dumps(p,indent=2).encode()+b'\0'
device=out/'Native Pitch Editor.amxd'
device.write_bytes(b'ampf'+struct.pack('<I',4)+b'aaaa'+b'meta'+struct.pack('<II',4,0)+b'ptch'+struct.pack('<I',len(data))+data)
print(device)
