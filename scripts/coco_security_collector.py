"""Read-only aggregate collection. Missing evidence is incomplete, never zero."""
from datetime import datetime, timedelta, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request

from coco_operations import NoRedirect, now, private_directory, read_regular
from coco_drive_backup import drive_freshness

REMOTE_SOURCES = ('erp_audit', 'export_events', 'ai_usage', 'auth_logs', 'auth_audit_logs', 'function_logs')
LOG_SOURCES = ('auth_logs', 'auth_audit_logs', 'function_logs')
EVENTS = ('privileged_role_change', 'sensitive_export', 'auth_denial', 'mfa_removed', 'ai_budget_rejected')
AI_METRICS = ('ai_calls', 'ai_failed', 'ai_expired', 'ai_reserved_microusd', 'ai_settled_charged_microusd', 'ai_input_tokens', 'ai_output_tokens')


class CollectionBusy(ValueError):
    pass


def private_json(path, limit=65536):
    info = Path(path).lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('COLLECTOR_PRIVATE_OWNER_FILE_REQUIRED')
    return json.loads(read_regular(path, limit))


def token(env, prefix):
    value, filename = env.get(prefix, ''), env.get(prefix + '_FILE', '')
    if bool(value) == bool(filename):
        raise ValueError('COLLECTOR_EXACTLY_ONE_TOKEN_SOURCE_REQUIRED')
    if filename:
        if not Path(filename).is_absolute():
            raise ValueError('COLLECTOR_ABSOLUTE_TOKEN_FILE_REQUIRED')
        fd = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 16384:
                raise ValueError('COLLECTOR_PRIVATE_TOKEN_REQUIRED')
            with os.fdopen(fd, 'rb', closefd=False) as source:
                value = source.read(16385).decode('ascii').strip()
        finally:
            os.close(fd)
    if not re.fullmatch(r'[A-Za-z0-9._~+/=-]{20,8192}', value):
        raise ValueError('COLLECTOR_TOKEN_INVALID')
    return value


def config(path):
    value = private_json(path)
    allowed = {'version','project_ref','window_minutes','ingestion_lag_minutes','thresholds','backup','certificates'}
    if not isinstance(value,dict) or set(value)-allowed or value.get('version') != 1 or not re.fullmatch('[a-z]{20}', value.get('project_ref', '')):
        raise ValueError('COLLECTOR_CONFIG_INVALID')
    for key, low, high in (('window_minutes', 1, 60), ('ingestion_lag_minutes', 1, 60)):
        if type(value.get(key)) is not int or not low <= value[key] <= high:
            raise ValueError('COLLECTOR_WINDOW_SETTINGS_INVALID')
    thresholds = value.get('thresholds')
    if not isinstance(thresholds, dict) or set(thresholds) - set(EVENTS) - {'backup_failed', 'certificate_expiring'}:
        raise ValueError('COLLECTOR_THRESHOLDS_INVALID')
    required = set(EVENTS)
    if value.get('backup') is not None:
        settings = value['backup']; required.add('backup_failed')
        if not isinstance(settings, dict) or set(settings)-{'root','max_age_hours','drive_folder_id'} or not Path(settings.get('root', '')).is_absolute() or type(settings.get('max_age_hours')) not in (int, float) or not 0 < settings['max_age_hours'] <= 8760:
            raise ValueError('COLLECTOR_BACKUP_CONFIG_INVALID')
        if settings.get('drive_folder_id') and not re.fullmatch('[A-Za-z0-9_-]{10,200}', settings['drive_folder_id']):
            raise ValueError('COLLECTOR_DRIVE_FOLDER_ID_INVALID')
    certificates = value.get('certificates', [])
    if not isinstance(certificates, list) or len(certificates) > 20:
        raise ValueError('COLLECTOR_CERTIFICATE_CONFIG_INVALID')
    if certificates:
        required.add('certificate_expiring')
    for item in certificates:
        if not isinstance(item, dict) or set(item)-{'path','warning_days'} or not Path(item.get('path', '')).is_absolute() or type(item.get('warning_days')) is not int or not 1 <= item['warning_days'] <= 365:
            raise ValueError('COLLECTOR_CERTIFICATE_CONFIG_INVALID')
    if set(thresholds) != required or any(type(x) is not int or not 1 <= x <= 100000000 for x in thresholds.values()):
        raise ValueError('COLLECTOR_ALL_CONFIGURED_THRESHOLDS_REQUIRED')
    return value


def atomic_replace(path, value):
    path = Path(path); private_directory(path.parent)
    if path.is_symlink():
        raise ValueError('COLLECTOR_OUTPUT_SYMLINK_REFUSED')
    fd, partial = tempfile.mkstemp(prefix='.collector-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(value, output, sort_keys=True); output.flush(); os.fsync(output.fileno())
        os.replace(partial, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        Path(partial).unlink(missing_ok=True)


def iso(value):
    return value.astimezone(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def time_filter(start, end):
    # Explicit half-open predicates prevent replay when the API rounds bounds.
    a, b = iso(start), iso(end)
    return f"timestamp >= parseDateTime64BestEffort('{a}',6,'UTC') AND timestamp < parseDateTime64BestEffort('{b}',6,'UTC')"


def probe_query(start, end):
    return """SELECT source,count() AS source_rows,
countIf((source='auth_logs' AND log_attributes['msg']='request completed' AND toInt32OrNull(log_attributes['status']) IS NOT NULL)
 OR (source='auth_audit_logs' AND mapContains(log_attributes,'auth_audit_event.action'))
 OR (source='function_logs' AND length(event_message)>0)) AS mapped_rows,
countIf((source='auth_logs' AND log_attributes['msg']='request completed' AND toInt32OrNull(log_attributes['status']) IS NULL)
 OR (source='auth_audit_logs' AND (NOT mapContains(log_attributes,'auth_audit_event.action') OR length(log_attributes['auth_audit_event.action'])=0))
 OR (source='function_logs' AND length(event_message)=0)) AS missing_fields
FROM logs WHERE source IN ('auth_logs','auth_audit_logs','function_logs') AND """ + time_filter(start, end) + ' GROUP BY source'


def events_query(start, end):
    return """SELECT
countIf(source='auth_logs' AND log_attributes['msg']='request completed'
 AND toInt32OrNull(log_attributes['status']) BETWEEN 400 AND 499) AS auth_denial,
countIf(source='auth_audit_logs' AND log_attributes['auth_audit_event.action'] IN ('factor_unenrolled','factor_deleted')) AS mfa_removed,
countIf(source='function_logs' AND JSONExtractString(event_message,'event')='ai_provider_admission_denied') AS ai_budget_rejected
FROM logs WHERE source IN ('auth_logs','auth_audit_logs','function_logs') AND """ + time_filter(start, end)


def scalar(value, maximum=100000000):
    if isinstance(value, str) and re.fullmatch('[0-9]{1,19}', value):
        value = int(value)
    if type(value) is not int or not 0 <= value <= maximum:
        raise ValueError('COLLECTOR_COUNTER_INVALID')
    return value


class Sources:
    def __init__(self, project, management_token, service_key, opener=None):
        if not re.fullmatch('[a-z]{20}', project):
            raise ValueError('COLLECTOR_PROJECT_REF_INVALID')
        self.project, self._management, self._service = project, management_token, service_key
        self.opener = opener or urllib.request.build_opener(NoRedirect())

    @classmethod
    def from_env(cls, project, env=None):
        env = os.environ if env is None else env
        return cls(project, token(env, 'COCO_MONITOR_ACCESS_TOKEN'), token(env, 'COCO_MONITOR_SERVICE_KEY'))

    def request(self, method, endpoint, bearer, payload=None, service=False):
        headers = {'Authorization': 'Bearer ' + bearer, 'Content-Type': 'application/json'}
        if service: headers['apikey'] = bearer
        body = None if payload is None else json.dumps(payload).encode()
        with self.opener.open(urllib.request.Request(endpoint, method=method, data=body, headers=headers), timeout=30) as response:
            raw = response.read(65537)
            if not 200 <= response.status < 300 or len(raw) > 65536:
                raise ValueError('COLLECTOR_SOURCE_RESPONSE_INVALID')
        return json.loads(raw)

    def database(self, start, end):
        value = self.request('POST', 'https://' + self.project + '.supabase.co/rest/v1/rpc/coco_security_aggregate', self._service,
                             {'p_start': iso(start), 'p_end': iso(end)}, service=True)
        if value.get('version') != 1 or value.get('coverage') != {'erp_audit': True, 'export_events': True, 'ai_usage': True}:
            raise ValueError('COLLECTOR_DATABASE_COVERAGE_INCOMPLETE')
        if set(value.get('counts', {})) != {'privileged_role_change', 'sensitive_export'} or set(value.get('metrics', {})) != set(AI_METRICS):
            raise ValueError('COLLECTOR_DATABASE_COUNTERS_INCOMPLETE')
        return ({key: scalar(count) for key, count in value['counts'].items()},
                {key: scalar(count, 10 ** 18) for key, count in value['metrics'].items()})

    def logs(self, query, start, end):
        params = urllib.parse.urlencode({'sql': query, 'iso_timestamp_start': iso(start), 'iso_timestamp_end': iso(end)})
        value = self.request('GET', 'https://api.supabase.com/v1/projects/' + self.project + '/analytics/endpoints/logs?' + params, self._management)
        if value.get('error') or not isinstance(value.get('result'), list):
            raise ValueError('COLLECTOR_LOGS_RESPONSE_INVALID')
        return value['result']

    def log_counters(self, start, end):
        probe_start = end - timedelta(hours=24)
        rows = self.logs(probe_query(probe_start, end), probe_start, end)
        seen = set()
        for row in rows:
            source = row.get('source')
            if source not in LOG_SOURCES or source in seen or scalar(row.get('missing_fields')) != 0 or not 0 < scalar(row.get('mapped_rows')) <= scalar(row.get('source_rows')):
                raise ValueError('COLLECTOR_LOG_SOURCE_UNMAPPED')
            seen.add(source)
        if seen != set(LOG_SOURCES):
            raise ValueError('COLLECTOR_LOG_SOURCE_UNAVAILABLE')
        values = self.logs(events_query(start, end), start, end)
        expected = {'auth_denial', 'mfa_removed', 'ai_budget_rejected'}
        if len(values) != 1 or set(values[0]) != expected:
            raise ValueError('COLLECTOR_LOG_COUNTERS_INCOMPLETE')
        return {key: scalar(value) for key, value in values[0].items()}


def certificate_count(certificates, clock):
    expiring = 0
    for item in certificates:
        body = read_regular(item['path'], 256 * 1024)
        if not body.startswith(b'-----BEGIN CERTIFICATE-----') or b'PRIVATE KEY' in body:
            raise ValueError('COLLECTOR_PUBLIC_PEM_CERTIFICATE_REQUIRED')
        result = subprocess.run(['openssl', 'x509', '-noout', '-enddate'], input=body, capture_output=True, timeout=5, check=True)
        match = re.fullmatch(rb'notAfter=([^\r\n]+)\s*', result.stdout)
        if not match:
            raise ValueError('COLLECTOR_CERTIFICATE_DATE_INVALID')
        expiry = datetime.strptime(match[1].decode('ascii'), '%b %d %H:%M:%S %Y %Z').replace(tzinfo=timezone.utc)
        if expiry <= clock + timedelta(days=item['warning_days']): expiring += 1
    return expiring


def collect(settings, sources, start, end, clock=None):
    clock = clock or now()
    coverage = {source: 'unavailable' for source in REMOTE_SOURCES}
    coverage.update(backup='not_configured', certificates='not_configured')
    counts, metrics = {}, {}
    try:
        db_counts, metrics = sources.database(start, end); counts.update(db_counts)
        coverage.update({key: 'complete' for key in ('erp_audit', 'export_events', 'ai_usage')})
    except Exception:
        pass  # Error bodies and URLs may contain provider details; never persist them.
    try:
        counts.update(sources.log_counters(start, end)); coverage.update({key: 'complete' for key in LOG_SOURCES})
    except Exception:
        pass
    if settings.get('backup') is not None:
        coverage['backup'] = 'unavailable'
        try:
            item = settings['backup']
            if item.get('drive_folder_id'):
                status = drive_freshness(item['root'], item['max_age_hours'], item['drive_folder_id'], clock)
            else:
                from coco_operations import freshness
                status = freshness(item['root'], item['max_age_hours'], clock)
            counts['backup_failed'] = 0 if status['healthy'] else 1
            coverage['backup'] = 'complete'
        except Exception:
            pass
    if settings.get('certificates'):
        coverage['certificates'] = 'unavailable'
        try:
            counts['certificate_expiring'] = certificate_count(settings['certificates'], clock); coverage['certificates'] = 'complete'
        except Exception:
            pass
    complete = all(status in ('complete', 'not_configured') for status in coverage.values())
    alerts = {key: value for key, value in counts.items() if value >= settings['thresholds'][key]}
    if not complete:
        counts['monitor_failed'] = 1; alerts['monitor_failed'] = 1
    return {'version': 2, 'observed_at': iso(clock), 'window_start': iso(start), 'window_end': iso(end),
            'source_project_hash': hashlib.sha256(settings['project_ref'].encode()).hexdigest(),
            'complete': complete, 'coverage': coverage, 'counts': counts, 'alert_counts': alerts, 'metrics': metrics}


def execute(settings, output, state_file, sources, clock=None):
    clock = clock or now()
    output, state_file = Path(output), Path(state_file)
    private_directory(output.parent); private_directory(state_file.parent)
    if output == state_file:
        raise ValueError('COLLECTOR_DISTINCT_OUTPUT_STATE_REQUIRED')
    lock = os.open(str(state_file) + '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(lock)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError('COLLECTOR_PRIVATE_LOCK_REQUIRED')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise CollectionBusy('COLLECTOR_ALREADY_RUNNING') from None
        end = (clock - timedelta(minutes=settings['ingestion_lag_minutes'])).replace(second=0, microsecond=0)
        start = end - timedelta(minutes=settings['window_minutes'])
        state_exists = state_file.exists()
        if state_exists:
            previous = private_json(state_file)
            if previous.get('version') != 1 or previous.get('project_ref') != settings['project_ref']:
                raise ValueError('COLLECTOR_STATE_PROJECT_MISMATCH')
            start = datetime.fromisoformat(previous['cursor_end'].replace('Z', '+00:00'))
            if start.tzinfo is None or start > end:
                raise ValueError('COLLECTOR_CURSOR_INVALID')
        existing = private_json(output) if output.exists() else None
        binding = hashlib.sha256(settings['project_ref'].encode()).hexdigest()
        if existing and existing.get('complete') is True and existing.get('source_project_hash') == binding:
            committed_end = datetime.fromisoformat(existing['window_end'].replace('Z', '+00:00'))
            if committed_end.tzinfo is None or committed_end > end:
                raise ValueError('COLLECTOR_OUTPUT_CURSOR_INVALID')
            # Output commits before the cursor. Recover from a crash between
            # those atomic writes instead of replaying or dropping a window.
            if not state_exists or committed_end > start:
                if state_exists and existing.get('window_start') != iso(start):
                    raise ValueError('COLLECTOR_OUTPUT_STATE_MISMATCH')
                start = committed_end
        if start == end:
            if not existing or existing.get('complete') is not True or existing.get('window_end') != iso(end) or existing.get('source_project_hash') != binding:
                raise ValueError('COLLECTOR_OUTPUT_STATE_MISMATCH')
            atomic_replace(state_file, {'version': 1, 'project_ref': settings['project_ref'], 'cursor_end': iso(end)})
            return existing
        if end - start > timedelta(hours=24):
            # Do not silently skip an outage longer than the supported logs range.
            raise ValueError('COLLECTOR_CATCHUP_EXCEEDS_SOURCE_RETENTION_WINDOW')
        if not state_exists:
            # Persist the pending lower bound before credentials or a source can
            # fail on the first run. A retry must not silently skip that window.
            atomic_replace(state_file, {'version': 1, 'project_ref': settings['project_ref'], 'cursor_end': iso(start)})
        if callable(sources):
            sources = sources()
        report = collect(settings, sources, start, end, clock)
        atomic_replace(output, report)
        if report['complete']:
            atomic_replace(state_file, {'version': 1, 'project_ref': settings['project_ref'], 'cursor_end': iso(end)})
        return report
    finally:
        os.close(lock)
