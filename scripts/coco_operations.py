"""Local-only backup supervision. Logs contain codes/counts, never business data."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import urllib.parse
import urllib.request

ARTIFACT = re.compile(r'(?:database\.dump|manifest\.json|object-[0-9]{6}|vault-[a-z0-9_-]{1,64})\.age\Z')
EVENTS = {'privileged_role_change', 'mfa_removed', 'sensitive_export', 'auth_denial', 'ai_budget_rejected', 'backup_failed', 'certificate_expiring', 'retention_failed', 'monitor_failed'}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('REDIRECT_REFUSED')


def now():
    return datetime.now(timezone.utc)


def atomic_json(destination, data):
    destination = Path(destination)
    partial = destination.with_name(destination.name + '.partial')
    fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(data, out, sort_keys=True)
            out.flush()
            os.fsync(out.fileno())
        # A completed backup is append-only; never replace a prior completion.
        os.link(partial, destination, follow_symlinks=False)
        partial.unlink()
        directory_fd = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise


def private_directory(path):
    path = Path(path)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('PRIVATE_OWNER_DIRECTORY_REQUIRED')
    return path


def read_regular(path, limit=1024 * 1024):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limit:
            raise ValueError('REGULAR_BOUNDED_FILE_REQUIRED')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            body = stream.read(limit + 1)
        if len(body) > limit:
            raise ValueError('FILE_TOO_LARGE')
        return body
    finally:
        os.close(fd)


def file_digest(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ValueError('REGULAR_FILE_REQUIRED')
        h = hashlib.sha256()
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(chunk)
        after = os.fstat(fd)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('ARTIFACT_CHANGED')
        return h.hexdigest()
    finally:
        os.close(fd)


def verify_bundle(path):
    path = private_directory(path)
    marker = json.loads(read_regular(path / 'COMPLETE.json', 32 * 1024 * 1024))
    if marker.get('format') != 'coco-encrypted-backup' or marker.get('version') != 2:
        raise ValueError('BACKUP_VERSION_REQUIRES_OPERATOR_REVIEW')
    artifacts = marker.get('artifacts')
    if not isinstance(artifacts, list) or not 2 <= len(artifacts) <= 100105:
        raise ValueError('BACKUP_ARTIFACTS_INVALID')
    names = set()
    for entry in artifacts:
        name, expected = entry.get('file', ''), entry.get('sha256', '')
        if not ARTIFACT.fullmatch(name) or name in names or not re.fullmatch('[a-f0-9]{64}', expected):
            raise ValueError('BACKUP_ARTIFACT_INVALID')
        names.add(name)
        if file_digest(path / name) != expected:
            raise ValueError('BACKUP_HASH_MISMATCH')
    if not {'database.dump.age', 'manifest.json.age'} <= names:
        raise ValueError('BACKUP_REQUIRED_ARTIFACT_MISSING')
    if set(p.name for p in path.iterdir()) != names | {'COMPLETE.json'}:
        raise ValueError('BACKUP_UNEXPECTED_ENTRY')
    finished = datetime.fromisoformat(marker['finished_at'])
    if finished.tzinfo is None or finished > now():
        raise ValueError('BACKUP_TIMESTAMP_INVALID')
    return marker, finished


def scan_backups(root):
    root = private_directory(root)
    valid, invalid = [], 0
    for path in root.iterdir():
        if not re.fullmatch(r'backup-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}', path.name):
            continue
        try:
            marker, finished = verify_bundle(path)
            valid.append((path, marker, finished))
        except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError):
            invalid += 1
    return sorted(valid, key=lambda x: x[2], reverse=True), invalid


def freshness(root, max_age_hours, clock=None):
    if not 0 < max_age_hours <= 8760:
        raise ValueError('MAX_AGE_INVALID')
    valid, invalid = scan_backups(root)
    clock = clock or now()
    age = None if not valid else max(0, (clock - valid[0][2]).total_seconds())
    return {'event': 'backup_health', 'healthy': age is not None and age <= max_age_hours * 3600,
            'complete_backups': len(valid), 'incomplete_backups': invalid,
            'latest_age_seconds': None if age is None else round(age), 'checked_at': clock.isoformat()}


def sanitized_alert(event, count=1, env=None, opener=None):
    env = os.environ if env is None else env
    if event not in EVENTS or not isinstance(count, int) or not 0 <= count <= 100000000:
        raise ValueError('ALERT_INVALID')
    endpoint = env.get('COCO_ALERT_WEBHOOK_URL', '')
    if not endpoint:
        return {'configured': False, 'sent': False}
    url = urllib.parse.urlsplit(endpoint)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError('ALERT_ENDPOINT_INVALID')
    body = json.dumps({'service': 'coco-erp', 'event': event, 'count': count, 'time': now().isoformat()}).encode()
    opener = opener or urllib.request.build_opener(NoRedirect())
    with opener.open(urllib.request.Request(endpoint, data=body, headers={'Content-Type': 'application/json'}), timeout=5) as response:
        if not 200 <= response.status < 300:
            raise ValueError('ALERT_DELIVERY_FAILED')
    return {'configured': True, 'sent': True}


def retention(root, policy_file, apply=False, clock=None):
    policy_info = Path(policy_file).lstat()
    if policy_info.st_uid != os.getuid() or policy_info.st_mode & 0o077:
        raise ValueError('PRIVATE_OWNER_RETENTION_POLICY_REQUIRED')
    policy = json.loads(read_regular(policy_file))
    days, keep = policy.get('delete_after_days'), policy.get('minimum_complete_copies')
    if policy.get('approved') is not True or type(days) is not int or not 1 <= days <= 36500 or type(keep) is not int or keep < 2:
        raise ValueError('APPROVED_RETENTION_POLICY_REQUIRED')
    valid, invalid = scan_backups(root)
    clock = clock or now()
    selected = [item for item in valid[keep:] if (clock - item[2]).total_seconds() > days * 86400]
    if apply:
        # Revalidate before deleting; only exact encrypted artifact names are removed.
        for path, marker, _ in selected:
            current, _ = verify_bundle(path)
            if marker != current:
                raise ValueError('BACKUP_CHANGED')
            for entry in marker['artifacts']:
                (path / entry['file']).unlink()
            (path / 'COMPLETE.json').unlink()
            path.rmdir()
    return {'event': 'backup_retention', 'mode': 'apply' if apply else 'dry-run', 'eligible_copies': len(selected),
            'preserved_complete_copies': len(valid) - (len(selected) if apply else 0), 'incomplete_copies_preserved': invalid,
            'checked_at': clock.isoformat()}


def security_signals(path, max_age_hours=2, require_collection=False):
    data = json.loads(read_regular(path))
    observed = datetime.fromisoformat(data['observed_at'])
    if data.get('version') not in (1,2) or observed.tzinfo is None or not 0 <= (now() - observed).total_seconds() <= max_age_hours * 3600:
        raise ValueError('SECURITY_SIGNALS_STALE_OR_INVALID')
    counts = data.get('counts', {})
    if not isinstance(counts, dict) or set(counts) - EVENTS or any(type(v) is not int or not 0 <= v <= 100000000 for v in counts.values()):
        raise ValueError('SECURITY_SIGNALS_INVALID')
    alerts = counts
    if data['version']==2:
        coverage = data.get('coverage')
        required = {'erp_audit','export_events','ai_usage','auth_logs','auth_audit_logs','function_logs'}
        if data.get('complete') is not True or not isinstance(coverage,dict) or not required <= set(coverage) or any(coverage[key]!='complete' for key in required) or any(value not in ('complete','not_configured') for value in coverage.values()):
            raise ValueError('SECURITY_COLLECTION_INCOMPLETE')
        measured = {'privileged_role_change','sensitive_export','auth_denial','mfa_removed','ai_budget_rejected'}
        if coverage.get('backup')=='complete': measured.add('backup_failed')
        if coverage.get('certificates')=='complete': measured.add('certificate_expiring')
        if not measured <= set(counts):
            raise ValueError('SECURITY_COLLECTION_COUNTERS_INCOMPLETE')
        metrics=data.get('metrics',{})
        expected={'ai_calls','ai_failed','ai_expired','ai_reserved_microusd','ai_settled_charged_microusd','ai_input_tokens','ai_output_tokens'}
        if set(metrics)!=expected or any(type(value) is not int or not 0<=value<=10**18 for value in metrics.values()):
            raise ValueError('SECURITY_COLLECTION_USAGE_INCOMPLETE')
        alerts = data.get('alert_counts')
        if not isinstance(alerts,dict) or set(alerts)-set(counts) or any(type(v) is not int or v!=counts[key] for key,v in alerts.items()):
            raise ValueError('SECURITY_ALERT_COUNTERS_INVALID')
    elif require_collection:
        raise ValueError('SECURITY_COLLECTOR_REQUIRED')
    return {'event': 'security_signals', 'observed_at': observed.isoformat(), 'counts': counts,
            'alert_counts': alerts, 'action_required': any(alerts.values()), 'checked_at': now().isoformat()}
