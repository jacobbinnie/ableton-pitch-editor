"""Known native integration profiles. Version labels alone never enable a profile."""
from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parents[1]
COPY = ROOT / 'build/Ableton Pitch Lab.app'
PROFILES = {
    'fca7d75481af0b561a51fdece48bc1fbd50c0e2c6ad04f34c6f794173be75d47': {
        'version': '12.4.5', 'resource_table': 0x10590f71f,
        'selector_background': 0x10358ca48, 'selector_text': 0x10358ca78,
        'selector_release': 0x10358bc80,
    },
    '2fa3ff55d5d73ec65df63b8fc56887af5bf1183e232addc877da256e2916070d': {
        'version': '12.4.6', 'resource_table': 0x10590f77f,
        'selector_background': 0x10358caa0, 'selector_text': 0x10358cad0,
        'selector_release': 0x10358bcd8,
    },
}


def identify(app):
    app = Path(app).expanduser().resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    with executable.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    label = info.get('CFBundleShortVersionString', 'unknown')
    profile = PROFILES.get(digest)
    if profile is None:
        raise ValueError(f'Unsupported Live build: {label} ({app}). No matching native profile. SHA-256: {digest}')
    if label.split(' ')[0] != profile['version']:
        raise ValueError(f'Live metadata does not match its executable: {label}')
    return dict(profile, sha256=digest, app=app, executable=executable, label=label)


def discover(explicit=None):
    if explicit:
        return identify(explicit)
    apps = sorted({p.resolve() for base in [Path('/Applications'), Path.home() / 'Applications']
                   for p in base.glob('Ableton Live*.app')})
    if not apps:
        raise ValueError('No Ableton Live installation found. Specify --live /path/to/Live.app.')
    if len(apps) != 1:
        raise ValueError('Multiple Live installations found. Select one with --live:\n' + '\n'.join(map(str, apps)))
    return identify(apps[0])
