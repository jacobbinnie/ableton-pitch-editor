#!/usr/bin/env python3
"""Bounded, offline LLDB disassembly of the verified Live arm64 tab paths.

Does not attach, launch, patch or execute Live. Refuses unrecognized binaries.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SHA256 = 'fca7d75481af0b561a51fdece48bc1fbd50c0e2c6ad04f34c6f794173be75d47'
# File virtual addresses, not ASLR-adjusted runtime addresses. Ends are exclusive.
RANGES = {
    'mode_selector_factory': (0x10358bd58, 0x10358bda8),
    'mode_selector_release': (0x10358bc80, 0x10358bcbc),
    'mode_selector_color_properties_and_setters': (0x10358c808, 0x10358cabc),
    'header_mode_filter': (0x103c93ce0, 0x103c93d20),
    'header_tab_callbacks': (0x103c93d58, 0x103c93f58),
    'header_mode_controller': (0x103c7ffbc, 0x103c80068),
    'effective_mode_and_rebuild_callbacks': (0x103c9457c, 0x103c946d4),
    'next_tab_callback': (0x103c95940, 0x103c959a0),
    'tab_cycling': (0x103c8f93c, 0x103c8fa34),
    'tab_modulo_helper': (0x1011e8e60, 0x1011e8e7c),
    'mode_change_callbacks': (0x103c95cc8, 0x103c95d78),
    'effective_mode_change_body': (0x103c85684, 0x103c85750),
    'editor_switch_candidate': (0x103c85760, 0x103c85928),
    'editor_selection_and_rebind': (0x103c85e44, 0x103c860e0),
    'rebuild_body_prefix': (0x103c8702c, 0x103c8733c),
    'header_factory': (0x103c7de78, 0x103c7decc),
    'manager_factory': (0x103c82318, 0x103c8236c),
    'manager_constructor_prefix': (0x103c825d4, 0x103c826d8),
    'clip_view_factory': (0x103c832e8, 0x103c8333c),
    'clip_view_constructor_prefix': (0x103c837b0, 0x103c83864),
    'waveform_factory': (0x103de1eec, 0x103de1f40),
    'platform_host_factory': (0x10179eb40, 0x10179eb94),
    'platform_host_constructor': (0x10179ec0c, 0x10179ecb0),
    'platform_host_listener_accessors': (0x10179f108, 0x10179f140),
    'platform_host_create_candidate': (0x10179f194, 0x10179f39c),
    'platform_host_hide_candidate': (0x10179f39c, 0x10179f414),
    'platform_host_native_handle_accessors': (0x10179f414, 0x10179f428),
    'platform_host_focus_callback': (0x1017aee24, 0x1017aee78),
    'plugin_platform_created_callback': (0x10312ea3c, 0x10312ea8c),
    'web_platform_created_callback': (0x103eaddb0, 0x103eade08),
    'web_platform_attachment_body': (0x103ea7f68, 0x103ea7ff4),
    'ax_proxy_owner_constructor': (0x1017479cc, 0x101747b00),
    'runtime_timeline_area_editor_binding': (0x103cc72cc, 0x103cc73a0),
    'runtime_warped_editor_context_binding': (0x103de5d0c, 0x103de5db8),
    'runtime_warped_editor_clear_binding': (0x103de63a4, 0x103de63bc),
    'runtime_warped_editor_area_binding': (0x103de2920, 0x103de2b20),
    'runtime_warped_editor_clip_binding': (0x103de5db8, 0x103de63a4),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=Path('/Applications/Ableton Live 12 Trial.app/Contents/MacOS/Live'))
    args = parser.parse_args()
    binary = args.binary.resolve()
    digest = hashlib.sha256()
    with binary.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != EXPECTED_SHA256:
        parser.error('Binary fingerprint differs; re-establish symbols before using these addresses.')
    output = ROOT / 'build' / 'research'
    output.mkdir(parents=True, exist_ok=True)
    # LLDB has its own command parser; escape paths for it, never invoke a shell.
    quoted = '"' + str(binary).replace('\\', '\\\\').replace('"', '\\"') + '"'
    commands = ['target create --arch arm64 ' + quoted]
    commands += [f'disassemble --start-address {start:#x} --end-address {end:#x}' for start, end in RANGES.values()]
    command_file = output / 'tabs.lldb'
    command_file.write_text('\n'.join(commands) + '\n')
    result = subprocess.run(['xcrun', 'lldb', '--batch', '--source', str(command_file)], capture_output=True, text=True, timeout=60)
    (output / 'tabs-disassembly.txt').write_text(result.stdout + result.stderr)
    if result.returncode or 'error:' in result.stderr or 'error:' in result.stdout:
        raise SystemExit('LLDB failed; inspect build/research/tabs-disassembly.txt')
    for start, _ in RANGES.values():
        if f'Live[{start:#x}]' not in result.stdout:
            raise SystemExit(f'Missing expected disassembly at {start:#x}')
    (output / 'manifest.json').write_text(json.dumps({
        'binary': str(binary), 'sha256': digest.hexdigest(), 'architecture': 'arm64',
        'kind': 'offline static evidence; no runtime confirmation',
        'ranges': {name: [hex(start), hex(end)] for name, (start, end) in RANGES.items()},
    }, indent=2) + '\n')
    print(f'Verified binary; captured {len(RANGES)} bounded code ranges in {output}')

if __name__ == '__main__':
    main()
