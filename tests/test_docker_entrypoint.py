"""Startup permission setup must not traverse or change the media library."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class DockerEntrypoint(unittest.TestCase):
    def test_startup_keeps_media_files_untouched(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            tools = root / 'bin'
            tools.mkdir()
            media = root / 'Media'
            (media / 'TV Shows').mkdir(parents=True)
            film = media / 'TV Shows' / 'episode.mkv'
            film.write_bytes(b'video')
            log = root / 'ownership.log'
            scripts = {
                'getent': '#!/bin/sh\nif [ "$1" = group ]; then echo "users:x:100:"; else echo "appuser:x:1026:100::/home/appuser:/bin/sh"; fi\n',
                'gosu': '#!/bin/sh\nshift\nexec "$@"\n',
                'chown': '#!/bin/sh\nprintf "%s\\n" "$*" >> "$OWNERSHIP_LOG"\n',
            }
            for name, source in scripts.items():
                path = tools / name
                path.write_text(source)
                path.chmod(0o755)
            entrypoint = Path(__file__).parents[1] / 'docker-entrypoint.sh'
            if not entrypoint.exists():
                installed = shutil.which('docker-entrypoint.sh')
                self.assertIsNotNone(installed, 'The image must include its startup script')
                entrypoint = Path(installed)
            result = subprocess.run(['sh', str(entrypoint), 'echo', 'app started'], env={
                **os.environ, 'PATH': f'{tools}:{os.environ["PATH"]}', 'PUID': '1026', 'PGID': '100',
                'TORRENTTUBE_DOWNLOAD_DIR': str(media), 'TORRENTTUBE_STATE_DIR': str(media / '.torrenttube'),
                'OWNERSHIP_LOG': str(log),
            }, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('app started', result.stdout)
            self.assertIn('Starting Torrent Tube as UID 1026', result.stdout)
            self.assertEqual(film.read_bytes(), b'video')
            self.assertFalse(log.exists(), 'Writable media folders must not need chown')
            self.assertTrue((media / '.torrenttube').is_dir())
