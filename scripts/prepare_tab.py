#!/usr/bin/env python3
"""Prepare a native Clip View button in a disposable Live application copy.

This demonstrates native layout insertion, not a working pitch editor. Only
GUI.alp's ClipContentHeader.xml entry changes. Executable code stays untouched.
Proprietary resources remain in ignored build/ and must not be distributed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import xml.etree.ElementTree as ET

from macho_read import Image
from live_compat import discover, identify

ROOT = Path(__file__).resolve().parents[1]
COPY = ROOT / 'build/Ableton Pitch Lab.app'


def scramble(data, key):
    result = bytearray(data)
    for pos, value in enumerate(result):
        k = key[(pos ^ (pos >> 8) ^ (pos >> 16) ^ (pos >> 24)) % len(key)]
        if value and value != k:
            result[pos] = value ^ k
    return bytes(result)


def prepare(source=None, *, original=None, write=True):
    profile = discover(source)
    source = profile['app']
    executable = profile['executable']
    print('Detected Live', profile['label'])
    if write:
        assert COPY.is_dir() and COPY.resolve() != source.resolve(), 'Create the disposable copy first'
        assert identify(COPY)['sha256'] == profile['sha256'], 'Experimental copy differs from selected Live installation'
    resource = Path('Contents/App-Resources/GUI.alp')
    if original is None:
        original = (source / resource).read_bytes()
    base = Image(executable).read(profile['resource_table'], 32)
    key = scramble(base, b'GUI.alp')
    decoded = scramble(original, key)
    assert decoded[:4] == b'pl-a'
    assert scramble(decoded, key) == original
    directory = struct.unpack_from('<Q', decoded, 4)[0]
    needle = 'ClipContentHeader.xml'.encode('utf-16le')
    assert decoded.count(needle) == 1
    name_pos = decoded.index(needle, directory)
    # Directory record: UTF-16 name, modification date (12 bytes), offset,
    # length. Keep every other record, item ID, and metadata byte unchanged.
    entry = name_pos + len(needle) + 12
    offset, length = struct.unpack_from('<QQ', decoded, entry)
    xml = decoded[offset:offset + length]
    tree = ET.fromstring(xml)
    if any(node.get('Value') == 'PitchEditorButton' for node in tree.iter('StringProperty')):
        raise ValueError('Selected source app already has Pitch Editor installed. Restore its original GUI.alp backup before preparing another copy.')
    selectors = [n for n in tree.iter('PropertiesNode')
                 if n.find('./Categories/PropertiesCategory/Properties/StringProperty[@Name="ViewId"]') is not None
                 and n.find('./Categories/PropertiesCategory/Properties/StringProperty[@Name="ViewId"]').get('Value') == 'EditorViewModeSelector']
    assert len(selectors) == 1 and selectors[0].get('TargetClassName') == 'ModeSwitchControl'
    selector = selectors[0]
    parent = next(n for n in tree.iter() if selector in list(n))
    button = ET.fromstring('''<PropertiesNode TargetClassName="ButtonControlSimple" Id="">
      <Categories>
        <PropertiesCategory Name="View Properties"><Properties>
          <PointProperty Name="Size" X="84" Y="15" />
          <StringProperty Name="ViewId" Value="PitchEditorButton" />
          <LocalizedStringProperty Name="Text" Value="Pitch Editor" />
          <LocalizedStringProperty Name="AxName" Value="Pitch Editor" />
          <LocalizedStringProperty Name="InfoTextHeader" Value="Pitch Editor" />
          <LocalizedStringProperty Name="InfoText" Value="Open the experimental Pitch Editor. Requires the matching Native Pitch Editor device." />
          <ViewExpressionProperty Name="ShowWhen" Value="ContentEditEnabled" />
          <EnumProperty Name="SelectionBehavior" Value="1" />
          <ColorNameProperty Name="ContrastFrameColor" ColorName="SurfaceBackground" />
          <ColorNameProperty Name="ButtonBackgroundColor" ColorName="SurfaceBackground" />
          <ColorNameProperty Name="TextFG Off" ColorName="DetailViewRulerMarkings" />
          <ColorNameProperty Name="TextFG Off Disabled" ColorName="DetailViewRulerMarkings" />
        </Properties></PropertiesCategory>
        <PropertiesCategory Name="Layout Properties"><Properties>
          <ResizePolicyProperty Name="HorizResizePolicy" PolicyName="FixToCurrentLength" Value1="0" Value2="0" />
          <ResizePolicyProperty Name="VertResizePolicy" PolicyName="FixToCurrentLength" Value1="0" Value2="0" />
        </Properties></PropertiesCategory>
      </Categories><Children />
    </PropertiesNode>''')
    # Use a full-height native frame, with the same fixed sizing as a tab.
    frame = ET.fromstring('''<PropertiesNode TargetClassName="BorderedCellView" Id="">
      <Categories><PropertiesCategory Name="View Properties"><Properties>
        <PointProperty Name="Size" X="86" Y="17" />
        <BorderProperty Name="Border" ColorName="56" Left="1" Right="1" Top="1" Bottom="1" Font="0" Title="" RoundedCornerSize="0" RoundedCorners="0" EdgesToDraw="15" CornerColorName="1"><BorderType Value="1" /></BorderProperty>
      </Properties></PropertiesCategory>
      <PropertiesCategory Name="Layout Properties"><Properties>
        <ResizePolicyProperty Name="HorizResizePolicy" PolicyName="FixToCurrentLength" Value1="0" Value2="0" />
        <ResizePolicyProperty Name="VertResizePolicy" PolicyName="FixToCurrentLength" Value1="0" Value2="0" />
        <BoolProperty Name="UseDefaultWeight" Value="false" />
        <FloatProperty Name="Weight" Value="0" />
      </Properties></PropertiesCategory></Categories><Children />
    </PropertiesNode>''')
    frame.find('Children').append(button)
    parent.insert(list(parent).index(selector) + 1, frame)
    row = next(n for n in tree.iter() if parent in list(n))
    row.find('./Categories/PropertiesCategory/Properties/IntProperty[@Name="Gap"]').set('Value', '0')
    ET.indent(tree, space='  ')
    modified = ET.tostring(tree, encoding='utf-8', xml_declaration=True) + b'\n'
    # Append the replacement payload before the directory. Existing payloads
    # retain their offsets, including the now-unreferenced original XML.
    table = bytearray(decoded[directory:])
    struct.pack_into('<QQ', table, entry - directory, directory, len(modified))
    new = bytearray(decoded[:directory] + modified + table)
    struct.pack_into('<Q', new, 4, directory + len(modified))
    assert new[12:directory] == decoded[12:directory]
    restored_table = bytearray(new[directory + len(modified):])
    struct.pack_into('<QQ', restored_table, entry - directory, offset, length)
    assert restored_table == decoded[directory:]
    ET.fromstring(new[directory:directory + len(modified)])
    encoded = scramble(new, key)
    assert scramble(encoded, key) == new
    if not write:
        return bytes(encoded)
    out = ROOT / 'build/research'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'ClipContentHeader.original.xml').write_bytes(xml)
    (out / 'ClipContentHeader.pitch.xml').write_bytes(modified)
    temporary = COPY / resource.with_suffix('.alp.tmp')
    temporary.write_bytes(encoded)
    temporary.replace(COPY / resource)
    manifest = {'source_executable_sha256': profile['sha256'], 'live_version': profile['label'],
                'source_gui_sha256': hashlib.sha256(original).hexdigest(),
                'modified_gui_sha256': hashlib.sha256(encoded).hexdigest(),
                'resource': 'ClipContentHeader.xml', 'original_offset': offset,
                'original_length': length, 'replacement_offset': directory,
                'replacement_length': len(modified), 'copy': str(COPY),
                'status': 'Native button layout only; no editor callback or DSP'}
    (out / 'native-tab-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', type=Path)
    args = parser.parse_args()
    prepare(args.live)
