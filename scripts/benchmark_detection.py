#!/usr/bin/env python3
"""Run deterministic pitch/voicing/segmentation evaluation without exporting audio."""
import argparse
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=root/'build/detection-benchmark.json')
parser.add_argument('--compare', type=Path)
args = parser.parse_args()
binary = root/'build/detection-benchmark'
binary.parent.mkdir(exist_ok=True)
subprocess.run(['xcrun', 'clang++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror',
                '-I'+str(root/'src'), str(root/'src/pitch_core.cpp'),
                str(root/'benchmarks/detection.cpp'), '-o', str(binary)], check=True)
report = json.loads(subprocess.check_output([str(binary)], text=True))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2)+'\n')
old = {}
if args.compare:
    old = {(x['name'], x['sample_rate']): x for x in json.loads(args.compare.read_text())['cases']}
print('case / rate | notes detected/truth | matched | pitch p95 cents | octave frames')
for row in report['cases']:
    key = row['name'], row['sample_rate']
    delta = f" (was {old[key]['matched_notes']} matched)" if key in old else ''
    print(f"{key[0]} / {key[1]} | {row['detected_notes']}/{row['truth_notes']} | "
          f"{row['matched_notes']}{delta} | {row['pitch_p95_cents']:.2f} | {row['octave_error_frames']}")
print(args.output)
