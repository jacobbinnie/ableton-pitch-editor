#!/usr/bin/env python3
"""Detect a known Live build before preparing the experimental app and device."""
import argparse
import re
import subprocess
import sys
from live_compat import COPY, ROOT, discover, identify
from prepare_tab import prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', help='Installed Live app; required if multiple installations exist')
    parser.add_argument('--check', action='store_true', help='Read-only compatibility check')
    args = parser.parse_args()
    profile = discover(args.live)
    print(f"Detected Live {profile['label']} at {profile['app']}", flush=True)
    print('Matched exact native profile (experimental, Apple Silicon).', flush=True)
    if args.check:
        return
    # Do not overwrite an existing copy of a different build.
    if COPY.exists() and identify(COPY)['sha256'] != profile['sha256']:
        raise ValueError('Experimental copy is a different build. Move it aside before setup.')
    running = subprocess.run(['pgrep', '-f', re.escape(str(COPY / 'Contents/MacOS/Live'))], capture_output=True)
    if running.returncode != 1:
        raise ValueError('Close the experimental Live copy before setup (or process check unavailable).')
    required = [ROOT/'vendor/max-sdk-base/c74support/max-includes/ext.h',
                ROOT/'vendor/rubberband-4.0.0/single/RubberBandSingle.cpp']
    if any(not p.exists() for p in required):
        raise ValueError('Build dependencies missing. Follow the README dependency setup first.')
    if not COPY.exists():
        COPY.parent.mkdir(exist_ok=True)
        subprocess.run(['cp', '-cR', str(profile['app']), str(COPY)], check=True)
    prepare(profile['app'])
    subprocess.run([sys.executable, str(ROOT/'scripts/build_native.py')], check=True)
    print(f'Ready: {COPY}\nLoad {ROOT / "build/Native Pitch Editor.amxd"} on the vocal track.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
