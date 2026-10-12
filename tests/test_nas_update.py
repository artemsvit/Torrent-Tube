"""Fast NAS updater checks using a fake Docker/Compose, with no NAS access."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class NASUpdate(unittest.TestCase):
    def run_update(self, state):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shutil.copy(Path(__file__).parents[1] / 'nas-update.sh', root / 'nas-update.sh')
            (root / 'docker-compose.yml').write_text('services: {}\n')
            data = root / 'state.json'
            data.write_text(json.dumps(state))
            fake = root / 'fake'
            fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['FAKE_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
s.setdefault('calls', []).append(a)
code = 0
if a[0] == '-f':
    override = Path(a[3]).read_text()
    assert 'image: artsvit/torrenttube:latest' in override
    if 'config' in a:
        code = 1 if s.get('bad_config') else 0
    elif 'up' in a:
        assert '--force-recreate' in a and '--no-build' in a
        code = 1 if s.get('bad_up') else 0
        if not code: s.update(image='sha256:new', running=True)
elif a[0] == 'inspect':
    print(str(s.get('running', False)).lower() if 'Running' in a[2] else s.get('image', 'sha256:old'))
elif a[0] == 'image': print('sha256:new')
elif a[0] == 'exec':
    if 'json' in a[-1]: print(s.get('streams', 0))
p.write_text(json.dumps(s))
sys.exit(code)
''')
            fake.chmod(0o755)
            result = subprocess.run(['sh', str(root / 'nas-update.sh')], env={**os.environ, 'DOCKER': str(fake), 'COMPOSE': str(fake), 'FAKE_STATE': str(data)}, capture_output=True, text=True, timeout=10)
            return result.returncode, json.loads(data.read_text()), (root / 'nas-update.log').read_text()

    def test_active_playback_does_not_pull_or_recreate(self):
        code, state, log = self.run_update({'running': True, 'streams': 1})
        self.assertEqual(code, 0, log)
        self.assertFalse(any(c[0] in ('pull', 'rmi') or 'up' in c for c in state['calls']))
        self.assertIn('deferred without pulling', log)

    def test_stopped_container_restarts_even_on_latest(self):
        code, state, log = self.run_update({'running': False, 'image': 'sha256:new'})
        self.assertEqual(code, 0, log)
        self.assertTrue(state['running'])
        self.assertIn('Updated and responding', log)

    def test_recreate_failure_keeps_old_image(self):
        code, state, log = self.run_update({'running': False, 'bad_up': True})
        self.assertEqual(code, 1, log)
        self.assertFalse(any(c[0] == 'rmi' or 'rm' in c for c in state['calls']))
        self.assertIn('Container recreation failed', log)

    def test_success_verifies_new_image_before_cleanup(self):
        code, state, log = self.run_update({'running': True, 'streams': 0})
        self.assertEqual(code, 0, log)
        self.assertEqual(state['image'], 'sha256:new')
        self.assertEqual(state['calls'][-1], ['rmi', 'sha256:old'])

    def test_invalid_compose_leaves_container_untouched(self):
        code, state, log = self.run_update({'bad_config': True})
        self.assertEqual(code, 1, log)
        self.assertFalse(any(c[0] in ('pull', 'rmi', 'inspect') or 'up' in c for c in state['calls']))
