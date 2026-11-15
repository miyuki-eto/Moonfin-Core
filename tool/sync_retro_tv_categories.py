"""Import authored Windows categories for the local TV preview; no remote writes."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--host', help='SSH host for the Windows source owner')
parser.add_argument('--remote-config', help='Absolute Windows home-rotation-config.json path')
parser.add_argument('--source-file', type=Path, help='Use an already exported category snapshot')
parser.add_argument('--discovery-file', type=Path,
                    default=Path(__file__).resolve().parents[2] / 'media/discovery_collections.json')
args = parser.parse_args()
if args.source_file:
    source = json.loads(args.source_file.read_text())
else:
    if not args.host or not args.remote_config:
        parser.error('Provide --source-file, or both --host and --remote-config')
    script = r"""$ErrorActionPreference='Stop'; [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding
$c=Get-Content -Encoding UTF8 -Raw '__CONFIG_PATH__' | ConvertFrom-Json
$c | Select-Object themes,directors,permanent_directors,minimum_director_films,beautiful_titles,mind_bending_titles,daily_movie_theme_rows,daily_tv_theme_rows | ConvertTo-Json -Depth 30 -Compress
"""
    script = script.replace("__CONFIG_PATH__", args.remote_config.replace("'", "''"))
    encoded = base64.b64encode(script.encode('utf-16le')).decode()
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', args.host,
                             'powershell.exe -NoProfile -EncodedCommand ' + encoded],
                            capture_output=True, check=True, timeout=40)
    source = json.loads(result.stdout.decode('utf-8-sig'))
# Store programming facts only. Server identity, accounts and credentials stay on Windows.
source = {k: source[k] for k in ('themes', 'directors')}
source['source'] = 'media/scripts/moonfin_home_rotation.py + Windows home-rotation-config.json'
if args.discovery_file.exists():
    for collection in json.loads(args.discovery_file.read_text())['collections']:
        source['themes'].append({'code': 'curated:' + collection['code'],
                                 'name': collection['name'],
                                 'tmdb_ids': [str(f['tmdb_id']) for f in collection['films']]})
    source['source'] += ' + media/discovery_collections.json'
root = Path(__file__).resolve().parents[1]
out = root / 'assets/programming/media_categories.json'
previous = json.loads(out.read_text()).get('channel_numbers', {}) if out.exists() else {}
names = ['cinema', 'tvReplay', *[t['code'] for t in source['themes']], 'franchises',
         *[f'decade:{d}' for d in range(1970, 2030, 10)],
         *['director:' + d for d in source['directors']]]
for name in names:
    if name not in previous:
        previous[name] = max(previous.values(), default=0) + 1
source['channel_numbers'] = previous
source['revision'] = hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest()
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(source, indent=2, ensure_ascii=False) + '\n')
print(f'Imported {len(source["themes"])} themes and {len(source["directors"])} directors into {out}')
