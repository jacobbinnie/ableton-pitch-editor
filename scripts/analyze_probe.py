#!/usr/bin/env python3
"""Summarize native owner identity across observed Sample/Envelopes snapshots.

Reads only the local probe log. Footer visibility is a mode indicator for the
controlled single-audio-clip experiment, not a general Live mode API.
"""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = re.compile(r'IDENTITY id=(\S+).*? owner=(0x[\da-f]+) ownerType=(\S+) ownerVTableFile=(0x[\da-f]+)')
FIELD = re.compile(r'FIELD path=(\S+) target=(0x[\da-f]+) type=(\S+) vtableFile=(0x[\da-f]+)')

def main():
    snapshots = []
    for block in (ROOT / 'probe.log').read_text().split('PROCESS ')[1:]:
        owners = {name: {'pointer': ptr, 'type': kind, 'vtable': table}
                  for name, ptr, kind, table in IDENTITY.findall(block)}
        if not owners:
            continue
        snapshots.append({
            'pid': int(re.search(r'pid=(\d+)', block)[1]),
            'modeIndicator': 'envelopes' if 'ClipContentFooter.EnvelopeControls' in block else 'sample',
            'owners': owners,
            'fields': {name: {'pointer': ptr, 'type': kind, 'vtable': table}
                       for name, ptr, kind, table in FIELD.findall(block)},
        })
    if not snapshots:
        raise SystemExit('No native identity snapshots. Load the probe and open an audio clip.')
    latest_pid = snapshots[-1]['pid']
    snapshots = [s for s in snapshots if s['pid'] == latest_pid]
    comparisons = []
    for before, after in zip(snapshots, snapshots[1:]):
        if before['modeIndicator'] == after['modeIndicator']:
            continue
        names = set(before['owners']) & set(after['owners'])
        comparisons.append({
            'from': before['modeIndicator'], 'to': after['modeIndicator'],
            'identicalOwners': sorted(n for n in names if before['owners'][n] == after['owners'][n]),
            'changedOwners': sorted(n for n in names if before['owners'][n] != after['owners'][n]),
        })
    result = {'pid': latest_pid, 'snapshots': snapshots, 'modeTransitions': comparisons,
              'limitation': 'Read-only pointer/type observations; no private methods invoked, no layer attached.'}
    output = ROOT / 'build/research/runtime-owners.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{len(snapshots)} snapshots; {len(comparisons)} observed mode transitions; {output}')
    for comparison in comparisons:
        print(json.dumps(comparison))
    if not comparisons:
        raise SystemExit('Switch Sample/Envelopes during the probe window to compare native owners.')

if __name__ == '__main__':
    main()
