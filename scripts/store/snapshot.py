#!/usr/bin/env python3
"""Build from a fixed source snapshot when another editor shares the checkout."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
destination = root / '.build/store-package'

def fingerprints():
    files = [root / 'Package.swift']
    files += sorted((root / 'Sources').rglob('*'))
    files += sorted((root / 'Tests').rglob('*'))
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in files if path.is_file()}

for attempt in range(3):
    before = fingerprints()
    with tempfile.TemporaryDirectory(prefix='store-snapshot-', dir=root / '.build') as temporary:
        stage = Path(temporary) / 'package'
        stage.mkdir()
        for relative in before:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / relative, target)
        copied = {relative: hashlib.sha256((stage / relative).read_bytes()).hexdigest() for relative in before}
        if copied != before or fingerprints() != before:
            continue
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(str(stage), destination)
    provenance = root / 'artifacts/store-readiness/source-snapshot.json'
    provenance.parent.mkdir(parents=True, exist_ok=True)
    provenance.write_text(json.dumps(before, indent=2) + '\n')
    print(f'固定编译快照：{len(before)} 个源文件。')
    break
else:
    sys.exit('源文件仍在同时修改；请待编辑完成后重新构建。')
