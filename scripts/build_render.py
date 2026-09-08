#!/usr/bin/env python3
"""Build the local rendering experiment. Rubber Band source remains in ignored vendor/."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
vendor=root/'vendor/rubberband-4.0.0'
if not (vendor/'single/RubberBandSingle.cpp').exists():
    raise SystemExit('Run python3 scripts/fetch_rubberband.py first')
build=root/'build'
build.mkdir(exist_ok=True)
common=['xcrun','clang++','-std=c++17','-O2','-I'+str(root/'src'),'-I'+str(vendor)]
obj=build/'rubberband-4.0.0.o'
subprocess.run(common+['-c',str(vendor/'single/RubberBandSingle.cpp'),'-o',str(obj)],check=True)
flags=common+['-Wall','-Wextra','-Werror']
for name,source in [('pitch-render-test','tests/pitch_render_test.cpp'),('pitch-render','src/pitch_render_cli.mm')]:
    cmd=flags+[str(root/'src/pitch_render.cpp'),str(root/'src/pitch_core.cpp'),str(root/source),str(obj),'-framework','Accelerate','-o',str(build/name)]
    if source.endswith('.mm'):cmd+=['-fobjc-arc','-framework','AVFoundation','-framework','Foundation']
    subprocess.run(cmd,check=True)
subprocess.run([str(build/'pitch-render-test')],check=True)

stream_test=build/'pitch-stream-test'
subprocess.run(flags+[str(root/'tests/pitch_stream_test.cpp'),str(root/'src/pitch_core.cpp'),str(obj),'-framework','Accelerate','-o',str(stream_test)],check=True)
subprocess.run([str(stream_test)],check=True)
expression_test=build/'pitch-expression-audio-test'
subprocess.run(flags+[str(root/'tests/pitch_expression_audio_test.cpp'),str(root/'src/pitch_core.cpp'),str(obj),'-framework','Accelerate','-o',str(expression_test)],check=True)
subprocess.run([str(expression_test)],check=True)
