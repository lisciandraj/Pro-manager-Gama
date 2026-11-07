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
import stat
import urllib.parse
import urllib.request
from coco_operations import NoRedirect, atomic_json, read_regular

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
    database = urllib.parse.urlsplit(env['COCO_DATABASE_URL'])
    project = url.netloc.split('.')[0]
    direct = database.hostname == 'db.' + url.netloc
    pooler = bool(database.hostname and database.hostname.endswith('.pooler.supabase.com') and urllib.parse.unquote(database.username or '') == 'postgres.' + project)
    if database.scheme not in ('postgres', 'postgresql') or not (direct or pooler) or database.query or database.fragment or database.path != '/postgres':
        raise ValueError('Database URL must identify the same Supabase project without query overrides')
    if database.port not in (None, 5432):
        raise ValueError('Use the direct or session pooler port for pg_dump')
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
        target.flush()
        os.fsync(target.fileno())
    # Never overwrite a completed artifact, even when a destination was reused.
    os.link(part, destination, follow_symlinks=False)
    part.unlink()

def vault_assets(path):
    """Read an operator-owned inventory, not secret values, into a bounded plan."""
    if not path:
        return []
    source = Path(path)
    info = source.lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Private vault inventory required')
    entries = json.loads(read_regular(source, 1024 * 1024))
    if not isinstance(entries, list) or not 1 <= len(entries) <= 100:
        raise ValueError('Vault inventory must name 1-100 assets')
    seen = set()
    for entry in entries:
        label = entry.get('id', '')
        if not re.fullmatch('[a-z0-9_-]{1,64}', label) or label in seen:
            raise ValueError('Invalid vault asset ID')
        seen.add(label)
        asset = Path(entry['path'])
        if not asset.is_absolute():
            raise ValueError('Vault asset must use an absolute path')
        info = asset.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError('Vault asset must be a private regular owner file')
        if info.st_size > 100 * 1024 * 1024:
            raise ValueError('Vault asset too large')
    return entries

def run(destination):
    origin = preflight()
    for binary in ('pg_dump', 'age'):
        if not shutil.which(binary):
            raise ValueError('Missing binary: ' + binary)
    version = subprocess.check_output(['pg_dump', '--version'], text=True)
    if not re.search(r'\b17\.', version):
        raise ValueError('Use reviewed PostgreSQL 17 pg_dump for this project')
    assets = vault_assets(os.environ.get('COCO_VAULT_ASSETS_FILE'))
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    recipient = os.environ['COCO_AGE_RECIPIENT']
    headers = {'apikey': os.environ['COCO_SERVICE_KEY'], 'Authorization': 'Bearer ' + os.environ['COCO_SERVICE_KEY']}
    started = dt.datetime.now(dt.timezone.utc).isoformat()

    def request(path, payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        return urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(origin + path, data=body, headers={**headers, 'Content-Type': 'application/json'}), timeout=60)

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
    encrypted_assets = []
    for entry in assets:
        name = 'vault-' + entry['id'] + '.age'
        fd = os.open(entry['path'], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_mode & 0o077 or info.st_uid != os.getuid() or info.st_size > 100 * 1024 * 1024:
                raise ValueError('Vault asset changed before encryption')
            with os.fdopen(fd, 'rb', closefd=False) as asset:
                encrypt(asset, destination/name, recipient)
            after_asset = os.fstat(fd)
            if (info.st_size, info.st_mtime_ns) != (after_asset.st_size, after_asset.st_mtime_ns):
                raise ValueError('Vault asset changed during encryption')
        finally:
            os.close(fd)
        encrypted_assets.append({'id': entry['id'], 'file': name, 'sha256': digest(destination/name)})
    root = Path(__file__).resolve().parent.parent
    configs = {str(p.relative_to(root)): p.read_text() for p in sorted((root/'config').rglob('*.json'))}
    manifest = {'format': 'coco-encrypted-backup', 'version': 2, 'started_at': started, 'finished_at': dt.datetime.now(dt.timezone.utc).isoformat(), 'project': origin, 'buckets': buckets, 'files': files, 'vault_assets': encrypted_assets, 'versioned_configs': configs, 'limitations': ['Not a transactional snapshot across DB and Storage', 'Vault inventory completeness must be approved by the owner', 'Restore rehearsal required before claiming RPO/RTO']}
    encrypt(io.BytesIO(json.dumps(manifest).encode()), destination/'manifest.json.age', recipient)
    artifacts = [{'file': f['file'], 'sha256': f['sha256']} for f in files + encrypted_assets]
    artifacts.append({'file': 'manifest.json.age', 'sha256': digest(destination/'manifest.json.age')})
    atomic_json(destination/'COMPLETE.json', {'format': 'coco-encrypted-backup', 'version': 2, 'encrypted_files': len(artifacts), 'artifacts': artifacts, 'finished_at': manifest['finished_at']})
    print(json.dumps({'complete': True, 'objects': len(objects), 'encrypted_files': len(artifacts), 'vault_assets': len(encrypted_assets)}))

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
