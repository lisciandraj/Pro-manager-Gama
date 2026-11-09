"""Encrypted Drive delivery contracts with a fake HTTP server; no live calls."""
from datetime import timedelta
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import coco_drive_backup as drive
import coco_operations as ops

spec = importlib.util.spec_from_file_location('drive_runner_test', ROOT / 'scripts/coco-operations.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
DESTINATION = 'private-destination-001'
TOKEN = 'ya29.fake-test-token-never-live'


class Response(io.BytesIO):
    def __init__(self, data=None, status=200, headers=None):
        super().__init__(json.dumps(data).encode() if data is not None else b'')
        self.status, self.headers = status, headers or {}


class FakeDrive:
    def __init__(self):
        self.calls, self.sessions, self.files, self.folders = [], {}, {}, {}
        self.public, self.bad_location, self.bad_checksum, self.bad_range, self.missing_checksum = False, False, False, False, False
        self.omit_file, self.extra_file, self.fail_after_bytes, self.md5_only = False, False, None, False
        self.sent_bytes = 0

    def metadata(self, record):
        body = record['body']
        result = {key: record[key] for key in ('id', 'name', 'parents', 'mimeType')}
        result.update(size=str(len(body)), trashed=False, md5Checksum=hashlib.md5(body, usedforsecurity=False).hexdigest())
        if not self.md5_only:
            result['sha256Checksum'] = hashlib.sha256(body).hexdigest()
        if self.bad_checksum:
            result['md5Checksum'] = '0' * 32
            if not self.md5_only: result['sha256Checksum'] = '0' * 64
        if self.missing_checksum:
            result.pop('sha256Checksum', None); result.pop('md5Checksum', None)
        return result

    def open(self, request, timeout):
        self.calls.append(request)
        assert 0 < timeout <= 60
        assert request.get_header('Authorization') == 'Bearer ' + TOKEN
        url = urllib.parse.urlsplit(request.full_url)
        assert url.netloc == 'www.googleapis.com'
        query = urllib.parse.parse_qs(url.query)
        method, path = request.method, url.path
        if path == '/drive/v3/files/' + DESTINATION:
            return Response({'id': DESTINATION, 'mimeType': drive.FOLDER_MIME, 'trashed': False, 'capabilities': {'canAddChildren': True}})
        if path == '/drive/v3/files/' + DESTINATION + '/permissions':
            return Response({'permissions': [{'type': 'anyone' if self.public else 'user', 'role': 'writer'}]})
        if path == '/drive/v3/files' and method == 'POST':
            data = json.loads(request.data)
            identifier = 'backup-set-folder-' + str(len(self.folders))
            self.folders[identifier] = {**data, 'id': identifier, 'trashed': False}
            return Response({'id': identifier})
        if path == '/upload/drive/v3/files' and method == 'POST':
            data = json.loads(request.data)
            upload_id = 'upload-session-' + str(len(self.sessions))
            self.sessions[upload_id] = {**data, 'id': 'ciphertext-file-' + str(len(self.sessions)), 'body': b'',
                                        'expected_size': int(request.get_header('X-upload-content-length'))}
            location = drive.UPLOAD + '?uploadType=resumable&upload_id=' + upload_id
            if self.bad_location: location = 'https://attacker.example.test/upload?uploadType=resumable&upload_id=secret'
            return Response({}, headers={'Location': location})
        if path == '/upload/drive/v3/files' and method == 'PUT':
            record = self.sessions[query['upload_id'][0]]
            offset, size = len(record['body']), record['expected_size']
            assert request.get_header('Content-range') == f'bytes {offset}-{offset + len(request.data) - 1}/{size}'
            assert len(request.data) <= drive.CHUNK_BYTES
            self.sent_bytes += len(request.data)
            if self.fail_after_bytes is not None and self.sent_bytes > self.fail_after_bytes:
                raise urllib.error.HTTPError(request.full_url, 503, 'temporary fake failure', {}, None)
            record['body'] += request.data
            if len(record['body']) < size:
                received = len(record['body']) - (2 if self.bad_range else 1)
                raise urllib.error.HTTPError(request.full_url, 308, 'Resume Incomplete', {'Range': f'bytes=0-{received}'}, io.BytesIO())
            self.files[record['id']] = record
            return Response({'id': record['id']}, status=201)
        if path == '/drive/v3/files' and method == 'GET':
            result = [self.metadata(record) for record in self.files.values()]
            if self.omit_file: result = result[:-1]
            if self.extra_file: result.append({'id': 'unexpected-file-000'})
            return Response({'files': result})
        identifier = path.removeprefix('/drive/v3/files/')
        if identifier in self.files and method == 'GET':
            return Response(self.metadata(self.files[identifier]))
        if identifier in self.folders:
            if method == 'PATCH':
                assert len(self.files) >= 2
                self.folders[identifier].update(json.loads(request.data))
            return Response(self.folders[identifier])
        raise AssertionError('Unexpected fake request: ' + method + ' ' + path)


class DriveBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.root.chmod(0o700)

    def bundle(self, suffix='aaaaaaaa', age_hours=1, large=False):
        finished = ops.now() - timedelta(hours=age_hours)
        bundle = self.root / ('backup-' + finished.strftime('%Y%m%dT%H%M%SZ') + '-' + suffix)
        bundle.mkdir(mode=0o700)
        artifacts = []
        for name in ('database.dump.age', 'manifest.json.age', 'vault-sri.age'):
            # Synthetic envelope only; no business data, keys or real encryption needed.
            content = drive.AGE_HEADER + b'synthetic-ciphertext' * (20000 if large and name == 'database.dump.age' else 5)
            (bundle / name).write_bytes(content); (bundle / name).chmod(0o600)
            artifacts.append({'file': name, 'sha256': ops.file_digest(bundle / name)})
        ops.atomic_json(bundle / 'COMPLETE.json', {'format': 'coco-encrypted-backup', 'version': 2,
            'finished_at': finished.isoformat(), 'artifacts': artifacts, 'unknown_private_field': 'must-never-be-uploaded'})
        return bundle

    def upload(self, bundle, fake=None):
        fake = fake or FakeDrive()
        return drive.upload_bundle(bundle, drive.DriveClient(DESTINATION, TOKEN, fake)), fake

    def test_complete_set_streamed_then_checksum_verified_before_commit(self):
        bundle = self.bundle(large=True)
        with mock.patch.object(drive, 'CHUNK_BYTES', 256 * 1024):
            result, fake = self.upload(bundle)
        self.assertTrue(result['complete']); self.assertEqual(result['encrypted_files'], 3)
        self.assertEqual(len(fake.files), 3)
        self.assertTrue(all(record['body'].startswith(drive.AGE_HEADER) for record in fake.files.values()))
        self.assertEqual({r['name'] for r in fake.files.values()}, {'database.dump.age', 'manifest.json.age', 'vault-sri.age'})
        self.assertTrue(any(r.method == 'PUT' and r.get_header('Content-range').startswith('bytes 262144-') for r in fake.calls))
        wire = b'\n'.join(r.data or b'' for r in fake.calls)
        self.assertNotIn(b'must-never-be-uploaded', wire); self.assertNotIn(b'COMPLETE.json', wire)
        commits = [i for i, r in enumerate(fake.calls) if r.method == 'PATCH']
        self.assertEqual(len(commits), 1)
        self.assertEqual(fake.calls[commits[0] - 1].method, 'GET')
        self.assertEqual(next(iter(fake.folders.values()))['appProperties']['coco_state'], 'complete')

    def test_provider_md5_supported_when_sha256_is_not_supplied(self):
        fake = FakeDrive(); fake.md5_only = True
        result, _ = self.upload(self.bundle(), fake)
        self.assertTrue(result['complete'])

    def test_incomplete_hash_mismatch_plaintext_and_extra_file_deny_before_network(self):
        for defect in ('missing_complete', 'hash', 'plaintext', 'extra', 'symlink'):
            with self.subTest(defect=defect):
                bundle = self.bundle(f'{len(list(self.root.iterdir())):08x}')
                if defect == 'missing_complete': (bundle / 'COMPLETE.json').unlink()
                elif defect == 'hash': (bundle / 'database.dump.age').write_bytes(b'changed')
                elif defect == 'extra': (bundle / 'identity.agekey').write_text('AGE-SECRET-KEY-NEVER-UPLOAD')
                elif defect == 'symlink':
                    (bundle / 'database.dump.age').unlink(); (bundle / 'database.dump.age').symlink_to(bundle / 'vault-sri.age')
                else:
                    (bundle / 'database.dump.age').write_bytes(b'plaintext-records-without-age-envelope')
                    marker = json.loads((bundle / 'COMPLETE.json').read_text())
                    marker['artifacts'][0]['sha256'] = ops.file_digest(bundle / 'database.dump.age')
                    (bundle / 'COMPLETE.json').write_text(json.dumps(marker))
                fake = FakeDrive()
                with self.assertRaises((ValueError, OSError)): self.upload(bundle, fake)
                self.assertEqual(fake.calls, [])

    def test_public_destination_refused_before_any_upload(self):
        fake = FakeDrive(); fake.public = True
        with self.assertRaisesRegex(ValueError, 'SHARING_REFUSED'): self.upload(self.bundle(), fake)
        self.assertEqual(fake.files, {}); self.assertEqual(fake.folders, {})

    def test_remote_failure_checksum_missing_entry_and_extra_entry_never_commit(self):
        for defect in ('bad_checksum', 'missing_checksum', 'omit_file', 'extra_file', 'failure'):
            with self.subTest(defect=defect):
                fake = FakeDrive()
                if defect == 'failure': fake.fail_after_bytes = 1
                else: setattr(fake, defect, True)
                with self.assertRaises(ValueError): self.upload(self.bundle(f'{len(list(self.root.iterdir())):08x}'), fake)
                self.assertFalse(any(r.method == 'PATCH' for r in fake.calls))
                self.assertEqual(next(iter(fake.folders.values()))['appProperties']['coco_state'], 'pending')

    def test_attacker_resumable_url_and_wrong_range_never_send_or_commit(self):
        bundle = self.bundle(large=True)
        fake = FakeDrive(); fake.bad_location = True
        with self.assertRaises(ValueError): self.upload(bundle, fake)
        self.assertFalse(any(r.method == 'PUT' for r in fake.calls))
        fake = FakeDrive(); fake.bad_range = True
        with mock.patch.object(drive, 'CHUNK_BYTES', 256 * 1024), self.assertRaisesRegex(ValueError, 'RANGE_MISMATCH'):
            self.upload(bundle, fake)
        self.assertFalse(any(r.method == 'PATCH' for r in fake.calls))

    def test_token_sources_private_file_and_no_redirect(self):
        token = self.root / 'token'; token.write_text(TOKEN + '\n'); token.chmod(0o600)
        self.assertEqual(drive.access_token({'COCO_DRIVE_TOKEN_FILE': str(token)}), TOKEN)
        self.assertEqual(drive.access_token({'COCO_DRIVE_ACCESS_TOKEN': TOKEN}), TOKEN)
        for env in ({}, {'COCO_DRIVE_ACCESS_TOKEN': TOKEN, 'COCO_DRIVE_TOKEN_FILE': str(token)},
                    {'COCO_DRIVE_ACCESS_TOKEN': TOKEN + '\nInjected: secret'}, {'COCO_DRIVE_TOKEN_FILE': 'relative-token'}):
            with self.assertRaises(ValueError): drive.access_token(env)
        token.chmod(0o644)
        with self.assertRaises(ValueError): drive.access_token({'COCO_DRIVE_TOKEN_FILE': str(token)})
        token.chmod(0o600); link = self.root / 'link'; link.symlink_to(token)
        with self.assertRaises(OSError): drive.access_token({'COCO_DRIVE_TOKEN_FILE': str(link)})
        os.link(token, self.root / 'hardlink')
        with self.assertRaises(ValueError): drive.access_token({'COCO_DRIVE_TOKEN_FILE': str(token)})
        with self.assertRaises(ValueError): ops.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example.test')
        for url in ('https://www.googleapis.com.evil.test/upload/drive/v3/files?uploadType=resumable&upload_id=x',
                    'http://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
                    drive.UPLOAD + '?uploadType=resumable&upload_id=x&upload_id=y'):
            with self.assertRaises(ValueError): drive.DriveClient._session_url(url)

    def test_local_freshness_requires_bound_drive_receipt_and_preserves_retention(self):
        bundle = self.bundle()
        self.assertFalse(drive.drive_freshness(self.root, 26, DESTINATION)['healthy'])
        with mock.patch.dict(os.environ, {'COCO_DRIVE_FOLDER_ID': DESTINATION}), \
             mock.patch.object(runner, 'sanitized_alert', return_value={'sent': True}) as alert, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(['check', '--root', str(self.root), '--max-age-hours', '26', '--drive', '--send-alert']), 1)
        alert.assert_called_once_with('backup_failed')
        result, _ = self.upload(bundle)
        drive.write_receipt(self.root, bundle, result)
        self.assertTrue(drive.drive_freshness(self.root, 26, DESTINATION)['healthy'])
        ops.verify_bundle(bundle)  # Receipt is outside the append-only backup set.
        self.assertEqual(len(ops.scan_backups(self.root)[0]), 1)
        self.assertFalse(drive.drive_freshness(self.root, 26, 'different-destination-001')['healthy'])
        self.assertFalse(drive.drive_freshness(self.root, 0.5, DESTINATION)['healthy'])
        marker = json.loads((bundle / 'COMPLETE.json').read_text()); marker['finished_at'] = (ops.now() - timedelta(minutes=5)).isoformat()
        (bundle / 'COMPLETE.json').write_text(json.dumps(marker))
        self.assertFalse(drive.drive_freshness(self.root, 26, DESTINATION)['healthy'])

    def test_cli_dry_run_never_loads_credentials_or_opens_network(self):
        bundle = self.bundle()
        with mock.patch.object(runner.DriveClient, 'from_env') as credentials, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(runner.main(['drive-upload', '--bundle', str(bundle)]), 0)
        credentials.assert_not_called()
        self.assertFalse(json.loads(output.getvalue())['production_access'])

    def test_downloaded_ciphertexts_reconstruct_marker_and_enter_existing_restore_workflow(self):
        bundle = self.bundle()
        result, fake = self.upload(bundle)
        metadata = self.root / 'folder-metadata.json'
        metadata.write_text(json.dumps(fake.folders[result['set_folder_id']])); metadata.chmod(0o600)
        (bundle / 'COMPLETE.json').unlink()
        # Model download into a fresh private directory after loss of the host.
        for record in fake.files.values():
            (bundle / record['name']).write_bytes(record['body'])
        preview = drive.reconstruct_marker(bundle, metadata, DESTINATION)
        self.assertEqual(preview['mode'], 'dry-run'); self.assertFalse((bundle / 'COMPLETE.json').exists())
        with mock.patch.dict(os.environ, {'COCO_DRIVE_FOLDER_ID': DESTINATION}), \
             mock.patch.object(runner.DriveClient, 'from_env') as credentials, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(['drive-recover-marker', '--bundle', str(bundle), '--folder-metadata', str(metadata), '--apply']), 0)
        credentials.assert_not_called()
        marker, _ = ops.verify_bundle(bundle)
        self.assertEqual(drive.marker_hash(marker), result['set_sha256'])

    def test_reconstruct_refuses_pending_tampered_missing_or_extra_ciphertext(self):
        for defect in ('pending', 'tampered', 'missing', 'extra'):
            with self.subTest(defect=defect):
                bundle = self.bundle(f'{len(list(self.root.iterdir())):08x}')
                result, fake = self.upload(bundle)
                folder = fake.folders[result['set_folder_id']]
                (bundle / 'COMPLETE.json').unlink()
                if defect == 'pending': folder['appProperties']['coco_state'] = 'pending'
                elif defect == 'tampered': (bundle / 'database.dump.age').write_bytes(drive.AGE_HEADER + b'changed-ciphertext')
                elif defect == 'missing': (bundle / 'vault-sri.age').unlink()
                else: (bundle / 'private-identity').write_text('AGE-SECRET-KEY-NEVER-UPLOAD')
                metadata = self.root / ('metadata-' + defect + '.json'); metadata.write_text(json.dumps(folder)); metadata.chmod(0o600)
                with self.assertRaises(ValueError): drive.reconstruct_marker(bundle, metadata, DESTINATION, apply=True)
                self.assertFalse((bundle / 'COMPLETE.json').exists())

    def test_scheduled_drive_failure_is_nonzero_sanitized_and_does_not_claim_success(self):
        module = mock.Mock()
        env = {'COCO_BACKUP_LOCATION_ATTESTED': 'off-provider', 'COCO_VAULT_ASSETS_FILE': '/private/inventory.json'}
        with mock.patch.dict(os.environ, env), mock.patch.object(runner.DriveClient, 'from_env'), \
             mock.patch.object(runner.importlib.util, 'spec_from_file_location'), \
             mock.patch.object(runner.importlib.util, 'module_from_spec', return_value=module), \
             mock.patch.object(runner, 'upload_bundle', side_effect=ValueError('must-not-print-token')), \
             mock.patch.object(runner, 'write_receipt') as receipt, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(runner.main(['backup', '--root', str(self.root), '--run', '--drive']), 1)
        module.run.assert_called_once(); self.assertEqual(module.run.call_args.kwargs, {'report': False}); receipt.assert_not_called()
        self.assertNotIn('must-not-print-token', output.getvalue())
        self.assertEqual(json.loads(output.getvalue())['event'], 'backup_failed')

    def test_missing_drive_credentials_refuse_before_database_export(self):
        env = {'COCO_BACKUP_LOCATION_ATTESTED': 'off-provider', 'COCO_VAULT_ASSETS_FILE': '/private/inventory.json'}
        with mock.patch.dict(os.environ, env), \
             mock.patch.object(runner.DriveClient, 'from_env', side_effect=ValueError('missing credential')), \
             mock.patch.object(runner.importlib.util, 'spec_from_file_location') as producer, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(['backup', '--root', str(self.root), '--run', '--drive']), 1)
        producer.assert_not_called()


if __name__ == '__main__':
    unittest.main()
