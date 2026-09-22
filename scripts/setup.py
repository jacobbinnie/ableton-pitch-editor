#!/usr/bin/env python3
"""Install or restore Pitch Editor in the selected installed Live app."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from live_compat import ROOT, discover
from prepare_tab import prepare


def digest(data):
    return hashlib.sha256(data).hexdigest()


def replace_resource(target, data):
    temporary = target.with_name(target.name + '.pitch-tmp')
    try:
        with temporary.open('xb') as stream:
            stream.write(data)
    except FileExistsError:
        raise ValueError(f'Previous temporary file exists; inspect it before retrying: {temporary}')
    try:
        shutil.copystat(target, temporary)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def read_backup(directory, target):
    original = (directory / 'GUI.alp.original').read_bytes()
    record = json.loads((directory / 'restore.json').read_text())
    if record['target'] != str(target) or digest(original) != record['original_sha256']:
        raise ValueError('Resource backup does not match this installation; refusing to overwrite it.')
    current_hash = digest(target.read_bytes())
    if current_hash not in (record['original_sha256'], record['patched_sha256']):
        raise ValueError('Live resources changed since installation; refusing to overwrite them.')
    return original, record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', help='Installed Live app; required if multiple installations exist')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Read-only compatibility check')
    mode.add_argument('--restore', action='store_true', help='Restore the backed-up UI resource')
    args = parser.parse_args()
    profile = discover(args.live)
    app = profile['app']
    print(f"Detected Live {profile['label']} at {app}", flush=True)
    print('Matched exact native profile (experimental, Apple Silicon).', flush=True)
    if args.check:
        return
    running = subprocess.run(['pgrep', '-f', re.escape(str(profile['executable']))], capture_output=True)
    if running.returncode != 1:
        raise ValueError('Close the selected Live app first (or process check unavailable).')
    target = app / 'Contents/App-Resources/GUI.alp'
    backup = Path.home() / 'Library/Application Support/Ableton Pitch Editor/backups' / profile['sha256']
    if (backup / 'GUI.alp.original').exists() or (backup / 'restore.json').exists():
        original, record = read_backup(backup, target)
    elif args.restore:
        raise ValueError('No backup found for this Live build. Nothing was changed.')
    else:
        original, record = target.read_bytes(), None
    if args.restore:
        replace_resource(target, original)
        print('Restored original Live UI resource. Remove the Pitch Editor device from your test track.')
        return
    required = [ROOT/'vendor/max-sdk-base/c74support/max-includes/ext.h',
                ROOT/'vendor/rubberband-4.0.0/single/RubberBandSingle.cpp']
    if any(not p.exists() for p in required):
        raise ValueError('Build dependencies missing. Follow the README dependency setup first.')
    patched = prepare(app, original=original, write=False)
    initial_hash = digest(target.read_bytes())
    # Finish compilation before modifying Live.
    subprocess.run([sys.executable, str(ROOT/'scripts/build_native.py'), '--live-app', str(app)], check=True)
    if digest(target.read_bytes()) != initial_hash:
        raise ValueError('Live resources changed during setup. Nothing was installed.')
    if record is None:
        backup.mkdir(parents=True, exist_ok=True)
        with (backup / 'GUI.alp.original').open('xb') as stream:
            stream.write(original)
    record = {'target': str(target), 'original_sha256': digest(original), 'patched_sha256': digest(patched)}
    metadata = backup / 'restore.json'
    # Keep both old and new known hashes valid if an update fails before replacement.
    previous = metadata.read_bytes() if metadata.exists() else None
    metadata.write_text(json.dumps(record, indent=2) + '\n')
    try:
        replace_resource(target, patched)
    except Exception:
        if previous is not None:
            metadata.write_bytes(previous)
        raise
    print(f'Ready: reopen {app}\nLoad {ROOT / "build/Native Pitch Editor.amxd"} on the vocal track.\nBackup: {backup}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        sys.exit(str(error))
