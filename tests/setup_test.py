"""Exercise direct install/restore without modifying a real Live installation."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
spec = importlib.util.spec_from_file_location('pitch_setup', Path(__file__).resolve().parents[1] / 'scripts/setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.app = self.root/'Live.app'
        self.target = self.app/'Contents/App-Resources/GUI.alp'
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b'original')
        for name in ['vendor/max-sdk-base/c74support/max-includes/ext.h', 'vendor/rubberband-4.0.0/single/RubberBandSingle.cpp']:
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        profile = {'app': self.app, 'label': 'fixture', 'sha256': 'fixture', 'executable': self.app/'Contents/MacOS/Live'}
        for mocked in [patch.object(setup, 'ROOT', self.root), patch.object(setup, 'discover', return_value=profile),
                       patch.object(setup, 'prepare', return_value=b'patched'), patch.object(Path, 'home', return_value=self.root),
                       patch.object(setup.subprocess, 'run', return_value=setup.subprocess.CompletedProcess([], 1))]:
            mocked.start()
            self.addCleanup(mocked.stop)

    def run_setup(self, *args):
        with patch.object(sys, 'argv', ['setup.py', *args]):
            setup.main()

    def test_install_repeat_restore(self):
        self.run_setup()
        self.assertEqual(self.target.read_bytes(), b'patched')
        self.run_setup()
        self.run_setup('--restore')
        self.assertEqual(self.target.read_bytes(), b'original')

    def test_refuses_changed_resource(self):
        self.run_setup()
        self.target.write_bytes(b'updated by another installer')
        with self.assertRaisesRegex(ValueError, 'resources changed'):
            self.run_setup('--restore')
        self.assertEqual(self.target.read_bytes(), b'updated by another installer')

    def test_no_backup_restore_is_non_destructive(self):
        with self.assertRaisesRegex(ValueError, 'No backup'):
            self.run_setup('--restore')
        self.assertEqual(self.target.read_bytes(), b'original')

    def test_failed_build_leaves_app_unchanged(self):
        def run(command, **kwargs):
            if command[0] == 'pgrep':
                return setup.subprocess.CompletedProcess(command, 1)
            raise setup.subprocess.CalledProcessError(1, command)
        with patch.object(setup.subprocess, 'run', side_effect=run):
            with self.assertRaises(setup.subprocess.CalledProcessError):
                self.run_setup()
        self.assertEqual(self.target.read_bytes(), b'original')


if __name__ == '__main__':
    unittest.main()
