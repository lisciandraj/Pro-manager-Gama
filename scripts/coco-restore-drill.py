#!/usr/bin/env python3
"""Restore an encrypted backup into an offline, loopback-only rehearsal stack.

Dry-run is the default. Never accepts a production target. Restoring data does not
attest application acceptance, Auth configuration or fiscal certification.
"""
import argparse
import io
import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from coco_operations import NoRedirect, atomic_json, read_regular, verify_bundle

LOOPBACK = {'127.0.0.1', 'localhost', '::1'}


def target_guard(database_url, storage_url, interfaces=None):
    db, storage = urllib.parse.urlsplit(database_url), urllib.parse.urlsplit(storage_url)
    if db.scheme not in ('postgres', 'postgresql') or db.hostname not in LOOPBACK or db.query or db.fragment:
        raise ValueError('ISOLATED_LOOPBACK_DATABASE_REQUIRED')
    if not re.fullmatch(r'/coco_restore_[a-z0-9_]{1,48}', db.path):
        raise ValueError('ISOLATED_DATABASE_NAME_REQUIRED')
    if storage.scheme not in ('http', 'https') or storage.hostname not in LOOPBACK or storage.username or storage.password or storage.query or storage.fragment or storage.path not in ('', '/'):
        raise ValueError('ISOLATED_LOOPBACK_STORAGE_REQUIRED')
    actual = set(name for _, name in socket.if_nameindex()) if interfaces is None else set(interfaces)
    if actual != {'lo'}:
        raise ValueError('OFFLINE_NETWORK_NAMESPACE_REQUIRED')
    return storage_url.rstrip('/')


def isolated_env(database_url):
    # No inherited PGSERVICE/PGHOST or provider credentials can redirect restore.
    allowed = {key: os.environ[key] for key in ('PATH', 'LANG', 'LC_ALL', 'SSL_CERT_FILE') if os.environ.get(key)}
    return {**allowed, 'PGDATABASE': database_url, 'PGCONNECT_TIMEOUT': '10', 'PGSSLMODE': 'disable'}


def decrypt_bytes(path, identity, limit):
    p = subprocess.Popen(['age', '--decrypt', '-i', str(identity), str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        out = p.stdout.read(limit + 1)
        if len(out) > limit:
            raise ValueError('DECRYPTED_ASSET_TOO_LARGE')
        if p.wait(timeout=60) != 0:
            raise ValueError('DECRYPTION_FAILED')
        return out
    finally:
        if p.poll() is None:
            p.kill(); p.wait()
        p.stdout.close()


def restore_database(path, identity, database_url):
    # Decrypted SQL is streamed directly to pg_restore; no plaintext dump file.
    decrypt = subprocess.Popen(['age', '--decrypt', '-i', str(identity), str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    restore = subprocess.Popen(['pg_restore', '--exit-on-error', '--single-transaction', '--no-owner', '--no-acl'],
                               stdin=decrypt.stdout, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               env=isolated_env(database_url))
    decrypt.stdout.close()
    try:
        result = restore.wait(timeout=1800)
        if decrypt.wait(timeout=30) != 0 or result != 0:
            raise RuntimeError('DATABASE_RESTORE_FAILED')
    finally:
        for process in (restore, decrypt):
            if process.poll() is None: process.kill(); process.wait()


def restore_storage(bundle, manifest, identity, origin, service_key, opener=None):
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    def call(path, payload=None, content_type='application/json', method='POST', extra_headers=None):
        request = urllib.request.Request(origin + path, data=payload, method=method, headers={
            'apikey': service_key, 'Authorization': 'Bearer ' + service_key, 'Content-Type': content_type,
            **(extra_headers or {})})
        with opener.open(request, timeout=60) as response:
            if not 200 <= response.status < 300: raise RuntimeError('STORAGE_RESTORE_FAILED')
            result = response.read(65537)
            if len(result) > 65536: raise RuntimeError('STORAGE_RESPONSE_TOO_LARGE')
            return result
    for bucket in manifest['buckets']:
        bucket_path = '/storage/v1/bucket/' + urllib.parse.quote(bucket['id'], safe='')
        # A full pg_dump already restores storage.buckets and storage.objects.
        # Reuse that metadata instead of failing with Duplicate/409. Only 404
        # permits creation; authentication and other failures remain fatal.
        try:
            existing = json.loads(call(bucket_path, method='GET'))
        except urllib.error.HTTPError as error:
            if error.code != 404: raise
            call('/storage/v1/bucket', json.dumps({'id': bucket['id'], 'name': bucket.get('name', bucket['id']), 'public': False}).encode())
        else:
            if existing.get('id') != bucket['id']:
                raise RuntimeError('STORAGE_BUCKET_ID_MISMATCH')
            # Rehearsal files are always private, including a restored public
            # source bucket. Other bucket settings are left unchanged.
            call(bucket_path, json.dumps({'public': False}).encode(), method='PUT')
    count = 0
    for item in manifest['files']:
        if not item.get('bucket'): continue
        content = decrypt_bytes(bundle/item['file'], identity, 100 * 1024 * 1024)
        path = '/storage/v1/object/' + urllib.parse.quote(item['bucket'], safe='') + '/' + urllib.parse.quote(item['name'], safe='/')
        # The ciphertext-bound manifest selects the exact object. Replacing
        # metadata left by pg_restore (or by an interrupted rehearsal) is safe
        # only inside the loopback/offline target guarded by main().
        call(path, content, 'application/octet-stream', extra_headers={'x-upsert': 'true'}); count += 1
    return count


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--identity', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--confirm-isolated', action='store_true')
    args = parser.parse_args(argv)
    try:
        marker, finished = verify_bundle(args.bundle)
        if not args.run:
            atomic_json(args.output, {'mode': 'dry-run', 'encrypted_integrity': 'passed',
                        'production_access': False, 'restore_executed': False,
                        'requires': ['offline namespace with only lo', 'isolated PostgreSQL17 coco_restore_* database',
                                     'isolated Auth/Storage API', 'private age identity', 'post-restore application acceptance']})
            print(json.dumps({'mode': 'dry-run', 'encrypted_integrity': 'passed', 'production_access': False})); return 0
        if not args.confirm_isolated or args.identity is None:
            raise ValueError('EXPLICIT_ISOLATED_RESTORE_REQUIRED')
        database = os.environ.get('COCO_RESTORE_DATABASE_URL', '')
        origin = target_guard(database, os.environ.get('COCO_RESTORE_STORAGE_URL', ''))
        key = os.environ.get('COCO_RESTORE_SERVICE_KEY', '')
        if not key: raise ValueError('ISOLATED_STORAGE_SERVICE_KEY_REQUIRED')
        # Private key is never copied into the restored stack or its report.
        identity_info = args.identity.lstat()
        if not stat.S_ISREG(identity_info.st_mode) or identity_info.st_nlink != 1 or identity_info.st_uid != os.getuid() or identity_info.st_mode & 0o077:
            raise ValueError('PRIVATE_AGE_IDENTITY_REQUIRED')
        for name in ('age', 'pg_restore'):
            if not shutil.which(name): raise ValueError('RESTORE_TOOL_MISSING')
        version = subprocess.check_output(['pg_restore', '--version'], text=True)
        if not re.search(r'\b17\.', version): raise ValueError('POSTGRES17_RESTORE_REQUIRED')
        manifest = json.loads(decrypt_bytes(args.bundle/'manifest.json.age', args.identity, 64 * 1024 * 1024))
        if manifest.get('format') != 'coco-encrypted-backup' or manifest.get('version') != 2:
            raise ValueError('BACKUP_MANIFEST_VERSION_INVALID')
        # Only artifact paths bound by the verified ciphertext inventory are read.
        expected = {a['file']: a['sha256'] for a in marker['artifacts']}
        for item in manifest['files'] + manifest.get('vault_assets', []):
            if item['file'] not in expected or expected[item['file']] != item['sha256']: raise ValueError('MANIFEST_ARTIFACT_MISMATCH')
        start = time.monotonic()
        restore_database(args.bundle/'database.dump.age', args.identity, database)
        objects = restore_storage(args.bundle, manifest, args.identity, origin, key)
        result = {'mode': 'isolated-restore', 'database_restore': 'passed', 'storage_objects_restored': objects,
                  'vault_assets_present': len(manifest.get('vault_assets', [])), 'vault_secrets_activated': False,
                  'duration_seconds': round(time.monotonic() - start), 'backup_finished_at': finished.isoformat(),
                  'status': 'application_acceptance_required', 'outbound_network': 'disabled',
                  'pending_acceptance': ['Auth fixture login/revocation', 'invoice and private attachment',
                                         'stock/payments reconciliation', 'two-customer access refusal',
                                         'SRI pruebas with dummy issuer only', 'measured business RPO/RTO'],
                  'production_access': False}
        atomic_json(args.output, result)
        print(json.dumps({'mode': result['mode'], 'status': result['status'], 'objects': objects})); return 0
    except Exception as error:
        print(json.dumps({'event': 'restore_drill_failed', 'code': type(error).__name__, 'production_access': False})); return 1


if __name__ == '__main__':
    raise SystemExit(main())
