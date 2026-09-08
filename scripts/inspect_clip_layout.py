#!/usr/bin/env python3
"""Read-only, fingerprint-checked extraction of the native Clip View structure."""
from pathlib import Path
import hashlib
import json
import struct
import xml.etree.ElementTree as ET

from macho_read import Image
from prepare_tab import EXPECTED, SOURCE, scramble

root = Path(__file__).resolve().parents[1]
binary = SOURCE / 'Contents/MacOS/Live'
if hashlib.sha256(binary.read_bytes()).hexdigest() != EXPECTED:
    raise SystemExit('Unsupported Live build; re-establish the resource decoder.')
raw = (SOURCE / 'Contents/App-Resources/GUI.alp').read_bytes()
key = scramble(Image(binary).read(0x10590f71f, 32), b'GUI.alp')
decoded = scramble(raw, key)
assert decoded[:4] == b'pl-a' and scramble(decoded, key) == raw
directory = struct.unpack_from('<Q', decoded, 4)[0]
out = root / 'build/research'
out.mkdir(parents=True, exist_ok=True)

def extract(name):
    needle = name.encode('utf-16le')
    matches = []
    pos = directory
    while (pos := decoded.find(needle, pos)) >= 0:
        matches.append(pos)
        pos += len(needle)
    assert len(matches) == 1, (name, 'ambiguous directory record')
    offset, size = struct.unpack_from('<QQ', decoded, matches[0] + len(needle) + 12)
    assert 12 <= offset < directory and offset + size <= directory
    xml = decoded[offset:offset + size]
    tree = ET.fromstring(xml)
    (out / name).write_bytes(xml)
    return tree

def properties(node):
    return {p.get('Name'): p.get('Value') for p in node.findall('./Categories/PropertiesCategory/Properties/*')}

def outline(tree):
    rows = []
    def visit(node, depth):
        if node.tag == 'PropertiesNode':
            p = properties(node)
            rows.append({'depth': depth, 'class': node.get('TargetClassName'),
                'properties': {k: v for k, v in p.items() if k in ('ViewId', 'ConnectTo', 'ShowWhen', 'SelectedIndexExpression')}})
            depth += 1
        for child in node:
            if child.tag in ('PropertiesNode', 'Children'):
                visit(child, depth)
    visit(tree, 0)
    return rows

trees = {name: extract(name) for name in ('ClipDetailView.xml', 'ClipContentArea.xml', 'ClipContentHeader.xml', 'ClipContentFooter.xml')}
slots = [n for n in trees['ClipContentArea.xml'].iter('PropertiesNode') if properties(n).get('ViewId') == '_ClipContentContainer']
assert len(slots) == 1 and slots[0].get('TargetClassName') == 'CellView'
assert not list(slots[0].find('Children')), 'Content is no longer constructed dynamically'
footer = [n for n in trees['ClipContentFooter.xml'].iter('PropertiesNode') if properties(n).get('ConnectTo') == 'EffectiveContentViewMode']
assert len(footer) == 1 and footer[0].get('TargetClassName') == 'CardView'
assert len(list(footer[0].find('Children'))) == 3
result = {'binary_sha256': EXPECTED, 'gui_sha256': hashlib.sha256(raw).hexdigest(),
    'kind': 'read-only resource structure; no runtime ownership inference',
    'content_slot': '_ClipContentContainer', 'footer_mode_cards': 3,
    'resources': {name: outline(tree) for name, tree in trees.items()}}
(out / 'clip-layout-manifest.json').write_text(json.dumps(result, indent=2) + '\n')
print('Verified: header → dynamic _ClipContentContainer → three-mode footer. Evidence in build/research/clip-layout-manifest.json')
