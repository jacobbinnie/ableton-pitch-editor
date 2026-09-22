"""Version labels must not authorize unknown binaries."""
import hashlib
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import live_compat


class CompatibilityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Live test.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/MacOS/Live').write_bytes(b'fixture executable')
        self.info = {'CFBundleExecutable': 'Live', 'CFBundleShortVersionString': '12.4.6 (fixture)'}
        self.write_info()
        self.digest = hashlib.sha256(b'fixture executable').hexdigest()
        self.profiles = {self.digest: {'version': '12.4.6', 'resource_table': 123}}

    def write_info(self):
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_known_fingerprint_selects_profile(self):
        with patch.dict(live_compat.PROFILES, self.profiles, clear=True):
            self.assertEqual(live_compat.discover(self.app)['resource_table'], 123)

    def test_unknown_binary_rejected_despite_matching_version(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported Live build'):
            live_compat.identify(self.app)

    def test_metadata_mismatch_rejected(self):
        self.info['CFBundleShortVersionString'] = '12.4.5'
        self.write_info()
        with patch.dict(live_compat.PROFILES, self.profiles, clear=True):
            with self.assertRaisesRegex(ValueError, 'metadata'):
                live_compat.identify(self.app)


if __name__ == '__main__':
    unittest.main()
