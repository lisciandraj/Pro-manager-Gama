"""Off-site delivery of complete age ciphertext sets to one private Drive folder.

No OAuth flow, plaintext backup, private age identity, remote deletion or network
access on import. The host supplies a short-lived access token out of band.
"""
import hashlib
from datetime import datetime
import json
import os
from pathlib import Path
import re
import stat
import time
import urllib.error
import urllib.parse
import urllib.request

from coco_operations import ARTIFACT, NoRedirect, atomic_json, file_digest, now, private_directory, read_regular, scan_backups, verify_bundle

API = 'https://www.googleapis.com/drive/v3'
UPLOAD = 'https://www.googleapis.com/upload/drive/v3/files'
FOLDER_MIME = 'application/vnd.google-apps.folder'
AGE_HEADER = b'age-encryption.org/v1\n'
CHUNK_BYTES = 8 * 1024 * 1024  # Drive requires multiples of 256 KiB except the last chunk.
ID = re.compile(r'[A-Za-z0-9_-]{10,200}\Z')
BACKUP_NAME = re.compile(r'backup-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}\Z')
FILE_FIELDS = 'id,name,mimeType,size,sha256Checksum,md5Checksum,parents,trashed'


def folder_id(env=None):
    value = (os.environ if env is None else env).get('COCO_DRIVE_FOLDER_ID', '')
    if not ID.fullmatch(value):
        raise ValueError('DRIVE_FOLDER_ID_REQUIRED')
    return value


def access_token(env=None):
    env = os.environ if env is None else env
    token, filename = env.get('COCO_DRIVE_ACCESS_TOKEN', ''), env.get('COCO_DRIVE_TOKEN_FILE', '')
    if bool(token) == bool(filename):
        raise ValueError('DRIVE_EXACTLY_ONE_TOKEN_SOURCE_REQUIRED')
    if filename:
        if not Path(filename).is_absolute():
            raise ValueError('DRIVE_ABSOLUTE_TOKEN_FILE_REQUIRED')
        # Open once without following links; check the same descriptor we read.
        fd = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 16384:
                raise ValueError('DRIVE_PRIVATE_OWNER_TOKEN_FILE_REQUIRED')
            with os.fdopen(fd, 'rb', closefd=False) as source:
                token = source.read(16385).decode('ascii').strip()
        finally:
            os.close(fd)
    if not re.fullmatch(r'[A-Za-z0-9._~+/=-]{20,8192}', token):
        raise ValueError('DRIVE_ACCESS_TOKEN_INVALID')
    return token


def marker_projection(marker):
    # Never copy arbitrary COMPLETE.json fields into Drive metadata or receipts.
    return {'format': 'coco-encrypted-backup', 'version': 2, 'finished_at': datetime.fromisoformat(marker['finished_at']).isoformat(),
            'artifacts': sorted(({'file': x['file'], 'sha256': x['sha256']} for x in marker['artifacts']), key=lambda x: x['file'])}


def marker_hash(marker):
    return hashlib.sha256(json.dumps(marker_projection(marker), sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def ciphertext_size(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_mode & 0o077 or not len(AGE_HEADER) < info.st_size <= 5 * 1024 ** 4:
            raise ValueError('DRIVE_PRIVATE_CIPHERTEXT_REQUIRED')
        if os.read(fd, len(AGE_HEADER)) != AGE_HEADER:
            raise ValueError('DRIVE_AGE_ENVELOPE_REQUIRED')
        return info.st_size
    finally:
        os.close(fd)


def encrypted_plan(bundle):
    bundle = Path(bundle)
    if not BACKUP_NAME.fullmatch(bundle.name):
        raise ValueError('DRIVE_NEUTRAL_BACKUP_DIRECTORY_NAME_REQUIRED')
    marker, finished = verify_bundle(bundle)
    total = 0
    for entry in marker['artifacts']:
        total += ciphertext_size(bundle / entry['file'])
    return marker, {'set_sha256': marker_hash(marker), 'finished_at': finished.isoformat(),
                    'encrypted_files': len(marker['artifacts']), 'ciphertext_bytes': total}


class DriveClient:
    def __init__(self, destination, token, opener=None, max_seconds=6900):
        if not ID.fullmatch(destination):
            raise ValueError('DRIVE_FOLDER_ID_REQUIRED')
        self.destination, self._token = destination, token
        self.opener = opener or urllib.request.build_opener(NoRedirect())
        self.deadline = time.monotonic() + max_seconds

    @classmethod
    def from_env(cls, env=None):
        return cls(folder_id(env), access_token(env))

    def _request(self, method, url, payload=None, headers=None, incomplete=False):
        # Every URL is either constructed below or validated as a resumable URL.
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('DRIVE_DELIVERY_DEADLINE_EXCEEDED')
        request = urllib.request.Request(url, data=payload, method=method,
                                        headers={'Authorization': 'Bearer ' + self._token, **(headers or {})})
        try:
            response = self.opener.open(request, timeout=min(60, remaining))
        except urllib.error.HTTPError as error:
            # Drive's resumable 308 has no Location. All redirects stay refused.
            if not incomplete or error.code != 308 or error.headers.get('Location'):
                raise ValueError('DRIVE_HTTP_REQUEST_FAILED') from None
            response = error
        with response:
            body = response.read(1024 * 1024 + 1)
            if len(body) > 1024 * 1024:
                raise ValueError('DRIVE_RESPONSE_TOO_LARGE')
            status = response.status
            if not 200 <= status < 300 and not (incomplete and status == 308 and not response.headers.get('Location')):
                raise ValueError('DRIVE_HTTP_REQUEST_FAILED')
            return status, response.headers, body

    def _json(self, method, path, payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        _, _, response = self._request(method, API + path, body, {'Content-Type': 'application/json'})
        value = json.loads(response)
        if not isinstance(value, dict):
            raise ValueError('DRIVE_RESPONSE_INVALID')
        return value

    def validate_destination(self):
        value = self._json('GET', '/files/' + self.destination + '?supportsAllDrives=true&fields=id,mimeType,trashed,capabilities(canAddChildren)')
        if value.get('id') != self.destination or value.get('mimeType') != FOLDER_MIME or value.get('trashed') is not False or value.get('capabilities', {}).get('canAddChildren') is not True:
            raise ValueError('DRIVE_WRITABLE_FOLDER_REQUIRED')
        count, page = 0, ''
        for _ in range(10):
            params = {'supportsAllDrives': 'true', 'pageSize': 100, 'fields': 'nextPageToken,permissions(type,role,deleted)'}
            if page:
                params['pageToken'] = page
            query = urllib.parse.urlencode(params)
            data = self._json('GET', '/files/' + self.destination + '/permissions?' + query)
            permissions = data.get('permissions')
            if not isinstance(permissions, list):
                raise ValueError('DRIVE_PERMISSIONS_NOT_VERIFIED')
            for permission in permissions:
                if permission.get('deleted'):
                    continue
                if permission.get('type') not in ('user', 'group'):
                    raise ValueError('DRIVE_PUBLIC_OR_DOMAIN_SHARING_REFUSED')
                count += 1
            page = data.get('nextPageToken', '')
            if not page:
                if not count:
                    raise ValueError('DRIVE_PERMISSIONS_NOT_VERIFIED')
                return
        raise ValueError('DRIVE_PERMISSIONS_LIMIT_EXCEEDED')

    @staticmethod
    def _session_url(value):
        url = urllib.parse.urlsplit(value or '')
        query = urllib.parse.parse_qs(url.query, strict_parsing=True)
        if url.scheme != 'https' or url.netloc != 'www.googleapis.com' or url.path != '/upload/drive/v3/files' or url.fragment or set(query) != {'uploadType', 'upload_id'} or query['uploadType'] != ['resumable'] or len(query['upload_id']) != 1 or not re.fullmatch(r'[!-~]{1,4096}', query['upload_id'][0]):
            raise ValueError('DRIVE_RESUMABLE_LOCATION_REFUSED')
        return value

    def upload(self, path, parent, expected):
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_uid != os.getuid() or before.st_mode & 0o077:
                raise ValueError('DRIVE_PRIVATE_CIPHERTEXT_REQUIRED')
            with os.fdopen(fd, 'rb', closefd=False) as source:
                sha, md5 = hashlib.sha256(), hashlib.md5(usedforsecurity=False)
                if source.read(len(AGE_HEADER)) != AGE_HEADER:
                    raise ValueError('DRIVE_AGE_ENVELOPE_REQUIRED')
                source.seek(0)
                for chunk in iter(lambda: source.read(CHUNK_BYTES), b''):
                    sha.update(chunk); md5.update(chunk)
                if sha.hexdigest() != expected:
                    raise ValueError('DRIVE_SOURCE_CHANGED')
                source.seek(0)
                metadata = json.dumps({'name': Path(path).name, 'parents': [parent], 'mimeType': 'application/octet-stream'}).encode()
                _, headers, _ = self._request('POST', UPLOAD + '?uploadType=resumable&supportsAllDrives=true&fields=id', metadata,
                                              {'Content-Type': 'application/json', 'X-Upload-Content-Type': 'application/octet-stream', 'X-Upload-Content-Length': str(before.st_size)})
                session = self._session_url(headers.get('Location'))
                offset, remote_id = 0, None
                while offset < before.st_size:
                    chunk = source.read(min(CHUNK_BYTES, before.st_size - offset))
                    if not chunk:
                        raise ValueError('DRIVE_SOURCE_CHANGED')
                    end = offset + len(chunk)
                    status, response_headers, body = self._request('PUT', session, chunk,
                        {'Content-Type': 'application/octet-stream', 'Content-Range': f'bytes {offset}-{end - 1}/{before.st_size}'}, incomplete=True)
                    if end < before.st_size:
                        if status != 308 or response_headers.get('Range') != f'bytes=0-{end - 1}':
                            raise ValueError('DRIVE_RESUMABLE_RANGE_MISMATCH')
                    else:
                        if status not in (200, 201):
                            raise ValueError('DRIVE_UPLOAD_INCOMPLETE')
                        remote_id = json.loads(body).get('id', '')
                        if not ID.fullmatch(remote_id):
                            raise ValueError('DRIVE_FILE_ID_INVALID')
                    offset = end
                after = os.fstat(fd)
                if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise ValueError('DRIVE_SOURCE_CHANGED')
            record = {'id': remote_id, 'name': Path(path).name, 'size': before.st_size, 'sha256': expected, 'md5': md5.hexdigest()}
            self.verify_file(self._json('GET', '/files/' + remote_id + '?supportsAllDrives=true&fields=' + FILE_FIELDS), parent, record)
            return record
        finally:
            os.close(fd)

    @staticmethod
    def verify_file(value, parent, expected):
        if value.get('id') != expected['id'] or value.get('name') != expected['name'] or value.get('mimeType') != 'application/octet-stream' or value.get('parents') != [parent] or value.get('trashed') is not False or str(value.get('size')) != str(expected['size']):
            raise ValueError('DRIVE_REMOTE_METADATA_MISMATCH')
        # Check server-calculated content hashes, never client-supplied properties.
        if value.get('sha256Checksum'):
            if value['sha256Checksum'] != expected['sha256']:
                raise ValueError('DRIVE_REMOTE_CHECKSUM_MISMATCH')
        elif value.get('md5Checksum') != expected['md5']:
            raise ValueError('DRIVE_REMOTE_CHECKSUM_MISSING_OR_MISMATCH')

    def verify_contents(self, parent, records):
        expected, seen, page = {r['id']: r for r in records}, set(), ''
        for _ in range(len(records) + 1):
            params = {'q': "'" + parent + "' in parents and trashed = false", 'pageSize': 1000,
                      'supportsAllDrives': 'true', 'includeItemsFromAllDrives': 'true', 'fields': 'nextPageToken,files(' + FILE_FIELDS + ')'}
            if page:
                params['pageToken'] = page
            query = urllib.parse.urlencode(params)
            value = self._json('GET', '/files?' + query)
            files = value.get('files')
            if not isinstance(files, list):
                raise ValueError('DRIVE_REMOTE_SET_INVALID')
            for item in files:
                identifier = item.get('id')
                if identifier not in expected or identifier in seen:
                    raise ValueError('DRIVE_REMOTE_SET_MISMATCH')
                self.verify_file(item, parent, expected[identifier]); seen.add(identifier)
            page = value.get('nextPageToken', '')
            if not page:
                if seen != set(expected):
                    raise ValueError('DRIVE_REMOTE_SET_INCOMPLETE')
                return
        raise ValueError('DRIVE_REMOTE_SET_LIMIT_EXCEEDED')


def upload_bundle(bundle, client):
    bundle = Path(bundle)
    marker, plan = encrypted_plan(bundle)  # All artifacts validated before any network request.
    client.validate_destination()
    properties = {'coco_format': 'encrypted-backup-v2', 'coco_state': 'pending', 'coco_set_sha256': plan['set_sha256'],
                  'coco_finished_at': plan['finished_at'], 'coco_artifacts': str(plan['encrypted_files'])}
    folder = client._json('POST', '/files?supportsAllDrives=true&fields=id',
                         {'name': bundle.name, 'mimeType': FOLDER_MIME, 'parents': [client.destination], 'appProperties': properties})
    identifier = folder.get('id', '')
    if not ID.fullmatch(identifier) or identifier == client.destination:
        raise ValueError('DRIVE_SET_FOLDER_INVALID')
    records = [client.upload(bundle / entry['file'], identifier, entry['sha256']) for entry in marker_projection(marker)['artifacts']]
    if len({record['id'] for record in records}) != len(records):
        raise ValueError('DRIVE_DUPLICATE_REMOTE_FILE')
    current, _ = verify_bundle(bundle)
    if marker_hash(current) != plan['set_sha256']:
        raise ValueError('DRIVE_SOURCE_CHANGED')
    client.verify_contents(identifier, records)
    properties['coco_state'] = 'complete'
    client._json('PATCH', '/files/' + identifier + '?supportsAllDrives=true&fields=id', {'appProperties': properties})
    confirmed = client._json('GET', '/files/' + identifier + '?supportsAllDrives=true&fields=id,name,parents,mimeType,trashed,appProperties')
    if confirmed.get('id') != identifier or confirmed.get('name') != bundle.name or confirmed.get('parents') != [client.destination] or confirmed.get('mimeType') != FOLDER_MIME or confirmed.get('trashed') is not False or confirmed.get('appProperties') != properties:
        raise ValueError('DRIVE_COMPLETION_NOT_CONFIRMED')
    return {'event': 'drive_backup_completed', 'complete': True, 'destination_folder_id': client.destination,
            'set_folder_id': identifier, **plan, 'verified_at': now().isoformat()}


def reconstruct_marker(bundle, metadata_file, destination, apply=False):
    """Offline import of downloaded ciphertext; metadata must come from Drive readback.

    Restores only the nonsecret local marker. No token or age identity is read.
    Like the original marker, the remote hash is an integrity check, not a signature.
    """
    bundle = private_directory(bundle)
    if not BACKUP_NAME.fullmatch(bundle.name) or not ID.fullmatch(destination):
        raise ValueError('DRIVE_RECOVERY_TARGET_INVALID')
    info = Path(metadata_file).lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('DRIVE_PRIVATE_METADATA_FILE_REQUIRED')
    metadata = json.loads(read_regular(metadata_file, 16384))
    props = metadata.get('appProperties', {})
    if not ID.fullmatch(metadata.get('id', '')) or metadata.get('name') != bundle.name or metadata.get('parents') != [destination] or metadata.get('mimeType') != FOLDER_MIME or metadata.get('trashed') is not False or props.get('coco_format') != 'encrypted-backup-v2' or props.get('coco_state') != 'complete' or not re.fullmatch('[a-f0-9]{64}', props.get('coco_set_sha256', '')):
        raise ValueError('DRIVE_COMPLETE_REMOTE_METADATA_REQUIRED')
    finished = datetime.fromisoformat(props['coco_finished_at'])
    if finished.tzinfo is None or finished > now():
        raise ValueError('DRIVE_RECOVERY_TIMESTAMP_INVALID')
    names = sorted(path.name for path in bundle.iterdir())
    if not 2 <= len(names) <= 100105 or str(len(names)) != props.get('coco_artifacts') or not {'database.dump.age', 'manifest.json.age'} <= set(names) or any(not ARTIFACT.fullmatch(name) for name in names):
        raise ValueError('DRIVE_RECOVERY_EXACT_CIPHERTEXT_SET_REQUIRED')
    artifacts = []
    for name in names:
        ciphertext_size(bundle / name)
        artifacts.append({'file': name, 'sha256': file_digest(bundle / name)})
    marker = {'format': 'coco-encrypted-backup', 'version': 2, 'finished_at': finished.isoformat(),
              'encrypted_files': len(artifacts), 'artifacts': artifacts}
    if marker_hash(marker) != props['coco_set_sha256']:
        raise ValueError('DRIVE_RECOVERY_SET_HASH_MISMATCH')
    if apply:
        atomic_json(bundle / 'COMPLETE.json', marker)
        verify_bundle(bundle)
    return {'event': 'drive_marker_reconstruction', 'mode': 'apply' if apply else 'dry-run',
            'production_access': False, 'encrypted_files': len(artifacts), 'set_sha256': props['coco_set_sha256']}


def write_receipt(root, bundle, result):
    root, bundle = private_directory(root), Path(bundle)
    if bundle.parent != root or not BACKUP_NAME.fullmatch(bundle.name):
        raise ValueError('DRIVE_RECEIPT_ROOT_MISMATCH')
    receipts = root / '.drive-receipts'
    try:
        receipts.mkdir(mode=0o700)
    except FileExistsError:
        pass
    private_directory(receipts)
    destination = receipts / (bundle.name + '.json')
    if destination.exists():
        previous = json.loads(read_regular(destination, 16384))
        if any(previous.get(key) != result.get(key) for key in ('destination_folder_id', 'set_sha256', 'finished_at', 'encrypted_files', 'ciphertext_bytes')):
            raise ValueError('DRIVE_RECEIPT_CONFLICT')
        return  # Preserve the first successful delivery's append-only receipt.
    atomic_json(destination, result)


def drive_freshness(root, max_age_hours, destination, clock=None):
    if not 0 < max_age_hours <= 24 * 365 or not ID.fullmatch(destination):
        raise ValueError('DRIVE_FRESHNESS_SETTINGS_INVALID')
    valid, invalid = scan_backups(root)
    clock = clock or now()
    latest_local = valid[0][2] if valid else None
    latest_drive, receipts = None, Path(root) / '.drive-receipts'
    if receipts.exists():
        private_directory(receipts)
        for path, marker, finished in valid:
            try:
                receipt = json.loads(read_regular(receipts / (path.name + '.json'), 16384))
                if receipt.get('event') != 'drive_backup_completed' or receipt.get('complete') is not True or receipt.get('destination_folder_id') != destination or receipt.get('set_sha256') != marker_hash(marker) or not ID.fullmatch(receipt.get('set_folder_id', '')):
                    continue
                latest_drive = finished
                break
            except (ValueError, OSError, TypeError, json.JSONDecodeError):
                continue
    local_age = None if latest_local is None else max(0, (clock - latest_local).total_seconds())
    drive_age = None if latest_drive is None else max(0, (clock - latest_drive).total_seconds())
    return {'event': 'backup_health', 'healthy': drive_age is not None and drive_age <= max_age_hours * 3600,
            'complete_backups': len(valid), 'incomplete_backups': invalid,
            'latest_age_seconds': None if local_age is None else round(local_age),
            'latest_drive_backup_age_seconds': None if drive_age is None else round(drive_age),
            'drive_evidence': 'local_receipt_of_verified_delivery; not a live remote availability check', 'checked_at': clock.isoformat()}
