#!/usr/bin/env python3
"""Check source exports for excluded local files and a usable one-commit repository."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix='quota-bar-source-check-') as directory:
    base = Path(directory)
    root = base / 'fixture with spaces'
    root.mkdir()
    env = {**os.environ, 'GIT_AUTHOR_NAME': 'Archive Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
           'GIT_COMMITTER_NAME': 'Archive Fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid'}

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(root), *arguments], env=env, stderr=subprocess.DEVNULL)

    git('init', '-b', 'main')
    (root / 'README.md').write_text('# QuotaBar\n')
    (root / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
    (root / 'run.sh').chmod(0o755)
    git('add', 'README.md', 'run.sh')
    git('commit', '-m', 'Initial commit')
    (root / '.env').write_text('local-only fixture\n')
    (root / '.build').mkdir()
    (root / '.build/cache').write_text('not source')
    git('config', 'remote.origin.url', 'https://example.invalid/private-source')
    output = base / 'quota-bar.zip'
    command = [sys.executable, str(ROOT / 'scripts/package-source.py'), '--root', str(root), '--output', str(output)]
    subprocess.run(command + ['--include-git'], check=True, stdout=subprocess.DEVNULL)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert 'quota-bar/.git/HEAD' in names
        assert not any('/.env' in name or '/.build/' in name or '/logs/' in name or '/hooks/' in name for name in names)
        assert b'private-source' not in archive.read('quota-bar/.git/config')
        assert archive.getinfo('quota-bar/run.sh').external_attr >> 16 & 0o111
        archive.extractall(base / 'extracted')
        for item in archive.infolist():
            (base / 'extracted' / item.filename).chmod((item.external_attr >> 16) & 0o777)
    extracted = base / 'extracted/quota-bar'
    assert subprocess.check_output(['git', '-C', str(extracted), 'rev-list', '--all', '--count']).strip() == b'1'
    assert not subprocess.check_output(['git', '-C', str(extracted), 'status', '--porcelain'])
    checksum = output.with_suffix('.zip.sha256').read_text().split()[0]
    assert checksum == hashlib.sha256(output.read_bytes()).hexdigest()
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    with zipfile.ZipFile(output) as archive:
        assert not any('/.git/' in name for name in archive.namelist())
    (root / 'README.md').write_text('# Another commit\n')
    git('add', 'README.md')
    git('commit', '-m', 'Another commit')
    rejected = subprocess.run(command + ['--include-git'], capture_output=True, text=True)
    assert rejected.returncode != 0 and 'exactly one commit object' in rejected.stderr
    # Removing a branch reference alone must not distribute old unreachable commits.
    git('reset', '--hard', 'HEAD~1')
    rejected = subprocess.run(command + ['--include-git'], capture_output=True, text=True)
    assert rejected.returncode != 0 and 'exactly one commit object' in rejected.stderr

print('Source archive contents, modes, checksum, clean Git export and history rejection checks passed')
