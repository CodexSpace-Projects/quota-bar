#!/usr/bin/env python3
"""Export a committed source snapshot, optionally with a clean one-commit Git repository."""

import argparse
from datetime import datetime, timezone
import hashlib
import io
from pathlib import Path
import subprocess
import tarfile
import zipfile


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, help='Defaults to dist/quota-bar-source.zip')
    parser.add_argument('--include-git', action='store_true', help='Include Git metadata; requires exactly one commit object.')
    options = parser.parse_args()
    root = options.root.resolve()
    output = (options.output or root / 'dist/quota-bar-source.zip').resolve()
    if subprocess.run(['git', '-C', str(root), 'diff', '--quiet', 'HEAD']).returncode:
        parser.error('Commit tracked changes before packaging.')
    if options.include_git:
        types = git(root, 'cat-file', '--batch-all-objects', '--batch-check=%(objecttype)').decode().splitlines()
        if types.count('commit') != 1:
            parser.error('--include-git requires exactly one commit object, including unreachable objects.')
        if git(root, 'rev-list', '--all', '--count').strip() != b'1':
            parser.error('--include-git requires exactly one reachable commit.')
    timestamp = int(git(root, 'show', '-s', '--format=%ct', 'HEAD'))
    stamp = datetime.fromtimestamp(max(timestamp, 315532800), timezone.utc).timetuple()[:6]
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = 'quota-bar/'
    entries = []
    source = io.BytesIO(git(root, 'archive', '--format=tar', 'HEAD'))
    with tarfile.open(fileobj=source) as archive:
        for item in archive:
            if item.isfile():
                entries.append((item.name, archive.extractfile(item).read(), 0o100000 | item.mode))
            elif item.issym():
                entries.append((item.name, item.linkname.encode(), 0o120777))
    if options.include_git:
        directory = Path(git(root, 'rev-parse', '--absolute-git-dir').decode().strip())
        # Do not distribute hooks, remotes, credential helpers, reflogs or local configuration.
        for name in ['HEAD', 'index', 'packed-refs']:
            path = directory / name
            if path.is_file():
                entries.append((f'.git/{name}', path.read_bytes(), 0o100644))
        for name in ['objects', 'refs']:
            for path in sorted((directory / name).rglob('*')):
                if path.is_file() and not path.is_symlink():
                    entries.append((f'.git/{path.relative_to(directory).as_posix()}', path.read_bytes(), 0o100644))
        config = '[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n\tlogallrefupdates = true\n'
        entries.append(('.git/config', config.encode(), 0o100644))
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data, mode in sorted(entries):
            item = zipfile.ZipInfo(prefix + name, date_time=stamp)
            item.create_system = 3
            item.external_attr = mode << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, data)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + '.sha256').write_text(f'{checksum}  {output.name}\n')
    print(f'{output}\nSHA-256: {checksum}\nFiles: {len(entries)}')


if __name__ == '__main__':
    main()
