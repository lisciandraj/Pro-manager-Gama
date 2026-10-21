"""Encrypted DB + Storage export. No plaintext archive and no credentials in argv/logs.

Dry-run by default. Real runs require pg_dump 17, age and four environment variables.
This creates a recovery candidate, not proof that a restoration succeeded.
"""
import argparse
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.parse
import urllib.request

REQUIRED = ('COCO_DATABASE_URL', 'COCO_SUPABASE_URL', 'COCO_SERVICE_KEY', 'COCO_AGE_RECIPIENT')

def preflight(env=os.environ):
    missing = [name for name in REQUIRED if not env.get(name)]
    if missing:
        raise ValueError('Missing settings: ' + ', '.join(missing))
    url = urllib.parse.urlsplit(env['COCO_SUPABASE_URL'])
    if url.scheme != 'https' or not re.fullmatch(r'[a-z0-9]{20}\.supabase\.co', url.netloc):
        raise ValueError('Expected the exact HTTPS Supabase project origin')
    if url.path not in ('', '/') or url.query or url.fragment:
        raise ValueError('Project URL must be an origin')
    if not env['COCO_AGE_RECIPIENT'].startswith(('age1', 'ssh-')):
        raise ValueError('Public age recipient required; do not supply its private identity')
    return url.scheme + '://' + url.netloc

def digest(file):
    h = hashlib.sha256()
    with open(file, 'rb') as source:
        for chunk in iter(lambda: source.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()

def encrypt(source, destination, recipient):
    part = Path(str(destination) + '.partial')
    with part.open('xb') as target:
        os.chmod(part, 0o600)
        p = subprocess.Popen(['age', '-r', recipient], stdin=subprocess.PIPE, stdout=target, stderr=subprocess.DEVNULL)
        try:
            shutil.copyfileobj(source, p.stdin, length=1024*1024)
            p.stdin.close()
            if p.wait() != 0:
                raise RuntimeError('Encryption failed')
        except BaseException:
            p.kill()
            p.wait()
            raise
    part.rename(destination)

def run(destination):
    origin = preflight()
    for binary in ('pg_dump', 'age'):
        if not shutil.which(binary):
            raise ValueError('Missing binary: ' + binary)
    version = subprocess.check_output(['pg_dump', '--version'], text=True)
    if not re.search(r'\b17\.', version):
        raise ValueError('Use reviewed PostgreSQL 17 pg_dump for this project')
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    recipient = os.environ['COCO_AGE_RECIPIENT']
    headers = {'apikey': os.environ['COCO_SERVICE_KEY'], 'Authorization': 'Bearer ' + os.environ['COCO_SERVICE_KEY']}
    started = dt.datetime.now(dt.timezone.utc).isoformat()

    def request(path, payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        return urllib.request.urlopen(urllib.request.Request(origin + path, data=body, headers={**headers, 'Content-Type': 'application/json'}), timeout=60)

    def inventory():
        with request('/storage/v1/bucket') as response:
            buckets = json.load(response)
        objects = []
        for bucket in buckets:
            prefixes = ['']
            while prefixes:
                prefix = prefixes.pop()
                offset = 0
                while True:
                    with request('/storage/v1/object/list/' + urllib.parse.quote(bucket['id'], safe=''), {'prefix': prefix, 'limit': 100, 'offset': offset, 'sortBy': {'column': 'name', 'order': 'asc'}}) as response:
                        rows = json.load(response)
                    for row in rows:
                        name = prefix + row['name']
                        if row.get('id') is None:
                            prefixes.append(name + '/')
                        else:
                            objects.append({'bucket': bucket['id'], 'name': name, 'updated_at': row.get('updated_at'), 'size': (row.get('metadata') or {}).get('size')})
                        if len(objects) + len(prefixes) > 100000:
                            raise RuntimeError('Inventory safety limit exceeded')
                    if len(rows) < 100:
                        break
                    offset += len(rows)
        return buckets, sorted(objects, key=lambda r: (r['bucket'], r['name']))

    buckets, objects = inventory()
    # libpq consumes the URL via environment, never the process argument list.
    env = {**os.environ, 'PGDATABASE': os.environ['COCO_DATABASE_URL'], 'PGCONNECT_TIMEOUT': '15', 'PGSSLMODE': 'require'}
    dump = subprocess.Popen(['pg_dump', '--format=custom', '--no-owner', '--no-acl'], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        encrypt(dump.stdout, destination/'database.dump.age', recipient)
        if dump.wait() != 0:
            raise RuntimeError('Database export failed; no completion manifest was written')
    finally:
        if dump.poll() is None:
            dump.kill()
            dump.wait()
    files = [{'file': 'database.dump.age', 'sha256': digest(destination/'database.dump.age')}]
    for index, item in enumerate(objects):
        name = f'object-{index:06}.age'
        url = '/storage/v1/object/' + urllib.parse.quote(item['bucket'], safe='') + '/' + urllib.parse.quote(item['name'], safe='/')
        with request(url) as response:
            encrypt(response, destination/name, recipient)
        files.append({**item, 'file': name, 'sha256': digest(destination/name)})
    _, after = inventory()
    if objects != after:
        raise RuntimeError('Storage changed during export; retry in a quiet window')
    root = Path(__file__).resolve().parent.parent
    configs = {str(p.relative_to(root)): p.read_text() for p in sorted((root/'config').rglob('*.json'))}
    manifest = {'started_at': started, 'finished_at': dt.datetime.now(dt.timezone.utc).isoformat(), 'project': origin, 'buckets': buckets, 'files': files, 'versioned_configs': configs, 'limitations': ['Not a transactional snapshot across DB and Storage', 'Provider secrets, DNS and SRI service configuration must be backed up separately', 'Restore rehearsal required before claiming RPO/RTO']}
    encrypt(io.BytesIO(json.dumps(manifest).encode()), destination/'manifest.json.age', recipient)
    (destination/'COMPLETE.json').write_text(json.dumps({'encrypted_files': len(files)+1, 'manifest_sha256': digest(destination/'manifest.json.age'), 'finished_at': manifest['finished_at']}))
    print(json.dumps({'complete': True, 'objects': len(objects), 'encrypted_files': len(files)+1}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    if not args.run:
        print(json.dumps({'mode': 'dry-run', 'settings_present': {key: bool(os.environ.get(key)) for key in REQUIRED}, 'binaries': {key: bool(shutil.which(key)) for key in ('pg_dump', 'age')}, 'production_access': False}))
    elif args.destination is None:
        parser.error('--destination required with --run')
    else:
        try:
            run(args.destination)
        except Exception as error:
            # Never print exception URLs, server bodies, or credential-bearing commands.
            print('Backup incomplete: ' + type(error).__name__ + '. Preserve encrypted partials; inspect privately.')
            raise SystemExit(1)
