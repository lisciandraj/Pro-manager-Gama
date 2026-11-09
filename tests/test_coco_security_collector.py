"""Actual collector HTTP contracts, source failure and cursor tests; no live calls."""
import contextlib
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import coco_operations as ops
import coco_security_collector as collector

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

cli = load('security_collection_cli_test', 'coco-collect-security.py')
monitor = load('security_collection_monitor_test', 'coco-operations.py')
PROJECT = 'abcdefghijklmnopqrst'
MANAGEMENT = 'sbp_fixture_management_token_never_live'
SERVICE = 'sb_secret_fixture_service_token_never_live'


class Response(io.BytesIO):
    status = 200
    def __init__(self, value): super().__init__(json.dumps(value).encode())


class FakeHTTP:
    def __init__(self):
        self.calls = []
        self.db_unavailable, self.missing_source, self.unmapped, self.malformed, self.rls = False, False, False, False, False
        self.usage = {key: 3 for key in collector.AI_METRICS}

    def open(self, request, timeout):
        self.calls.append(request)
        assert timeout == 30
        url = urllib.parse.urlsplit(request.full_url)
        if url.netloc == PROJECT + '.supabase.co':
            assert request.method == 'POST' and url.path == '/rest/v1/rpc/coco_security_aggregate'
            assert request.get_header('Authorization') == 'Bearer ' + SERVICE
            assert request.get_header('Apikey') == SERVICE
            assert set(json.loads(request.data)) == {'p_start', 'p_end'}
            if self.db_unavailable:
                raise urllib.error.HTTPError(request.full_url, 503, 'private-provider-body-secret', {}, None)
            coverage = {'erp_audit': True, 'export_events': True, 'ai_usage': not self.rls}
            return Response({'version': 1, 'coverage': coverage, 'counts': {'privileged_role_change': 2, 'sensitive_export': 1}, 'metrics': self.usage})
        assert url.netloc == 'api.supabase.com'
        assert request.method == 'GET' and url.path == '/v1/projects/' + PROJECT + '/analytics/endpoints/logs'
        assert request.get_header('Authorization') == 'Bearer ' + MANAGEMENT
        assert request.get_header('Apikey') is None
        params = urllib.parse.parse_qs(url.query)
        assert set(params) == {'sql', 'iso_timestamp_start', 'iso_timestamp_end'}
        query = params['sql'][0]
        assert 'FROM logs' in query and 'count()' in query or 'countIf(' in query
        assert 'count(*)' not in query and 'SELECT *' not in query
        assert 'parseDateTime64BestEffort(' in query and 'timestamp < ' in query
        start = datetime.fromisoformat(params['iso_timestamp_start'][0].replace('Z', '+00:00'))
        end = datetime.fromisoformat(params['iso_timestamp_end'][0].replace('Z', '+00:00'))
        assert start.second == 0 and end.second == 0 and timedelta(0) < end-start <= timedelta(hours=24)
        if self.malformed: return Response({'result': [], 'error': 'secret business body must not be persisted'})
        if 'GROUP BY source' in query:
            rows = [{'source': source, 'source_rows': '10', 'mapped_rows': '9', 'missing_fields': '0'} for source in collector.LOG_SOURCES]
            if self.missing_source: rows.pop()
            if self.unmapped: rows[0]['missing_fields'] = '1'
            return Response({'result': rows})
        return Response({'result': [{'auth_denial': '12', 'mfa_removed': '1', 'ai_budget_rejected': '2'}]})


class SecurityCollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.root.chmod(0o700)
        self.clock = ops.now().replace(second=0, microsecond=0)
        self.settings = {'version': 1, 'project_ref': PROJECT, 'window_minutes': 15, 'ingestion_lag_minutes': 3,
                         'thresholds': {key: 1 for key in collector.EVENTS}}
        self.settings['thresholds']['auth_denial'] = 20
        self.fake = FakeHTTP()
        self.sources = collector.Sources(PROJECT, MANAGEMENT, SERVICE, self.fake)
        self.output, self.state = self.root / 'signals.json', self.root / 'state.json'

    def collect(self):
        return collector.collect(self.settings, self.sources, self.clock-timedelta(minutes=18), self.clock-timedelta(minutes=3), self.clock)

    def write_config(self):
        path = self.root / 'config.json'; path.write_text(json.dumps(self.settings)); path.chmod(0o600)
        return path

    def test_only_aggregates_from_supported_api_and_real_rpc_reach_output(self):
        report = self.collect()
        self.assertTrue(report['complete']); self.assertEqual(report['counts']['auth_denial'], 12)
        self.assertNotIn('auth_denial', report['alert_counts'])  # Below explicit threshold.
        self.assertEqual(report['alert_counts']['mfa_removed'], 1)
        self.assertEqual(report['metrics']['ai_calls'], 3)
        self.assertEqual(len(self.fake.calls), 3)
        serialized = json.dumps(report)
        for value in (MANAGEMENT, SERVICE, 'actor_id', 'email', 'event_message', 'private-provider'):
            self.assertNotIn(value, serialized)
        collector.atomic_replace(self.output, report)
        result = ops.security_signals(self.output, require_collection=True)
        self.assertEqual(result['alert_counts'], report['alert_counts'])
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)

    def test_unavailable_unmapped_or_rls_sources_never_become_zero_healthy(self):
        for issue in ('db_unavailable', 'missing_source', 'unmapped', 'malformed', 'rls'):
            with self.subTest(issue=issue):
                fake = FakeHTTP(); setattr(fake, issue, True)
                sources = collector.Sources(PROJECT, MANAGEMENT, SERVICE, fake)
                report = collector.collect(self.settings, sources, self.clock-timedelta(minutes=18), self.clock-timedelta(minutes=3), self.clock)
                self.assertFalse(report['complete']); self.assertEqual(report['counts']['monitor_failed'], 1)
                if issue in ('db_unavailable', 'rls'):
                    self.assertNotIn('privileged_role_change', report['counts']); self.assertNotIn('ai_calls', report['metrics'])
                else:
                    self.assertNotIn('auth_denial', report['counts']); self.assertNotIn('mfa_removed', report['counts'])
                collector.atomic_replace(self.output, report)
                with self.assertRaises(ValueError): ops.security_signals(self.output, require_collection=True)
                self.assertNotIn('secret', json.dumps(report))

    def test_cursor_advances_only_on_complete_half_open_windows(self):
        first = collector.execute(self.settings, self.output, self.state, self.sources, self.clock)
        end = first['window_end']; count = len(self.fake.calls)
        self.assertEqual(collector.execute(self.settings, self.output, self.state, self.sources, self.clock), first)
        self.assertEqual(len(self.fake.calls), count)
        second = collector.execute(self.settings, self.output, self.state, self.sources, self.clock+timedelta(minutes=15))
        self.assertEqual(second['window_start'], end)
        previous = self.state.read_bytes(); self.fake.db_unavailable = True
        failed = collector.execute(self.settings, self.output, self.state, self.sources, self.clock+timedelta(minutes=30))
        self.assertFalse(failed['complete']); self.assertEqual(self.state.read_bytes(), previous)
        self.fake.db_unavailable = False
        resumed = collector.execute(self.settings, self.output, self.state, self.sources, self.clock+timedelta(minutes=45))
        self.assertEqual(resumed['window_start'], second['window_end'])

    def test_excessive_outage_refused_without_advancing_cursor(self):
        collector.execute(self.settings, self.output, self.state, self.sources, self.clock)
        previous = self.state.read_bytes()
        with self.assertRaisesRegex(ValueError, 'CATCHUP'):
            collector.execute(self.settings, self.output, self.state, self.sources, self.clock+timedelta(hours=25))
        self.assertEqual(self.state.read_bytes(), previous)

    def test_committed_output_recovers_cursor_after_interrupted_state_write(self):
        first = collector.execute(self.settings,self.output,self.state,self.sources,self.clock)
        self.state.unlink()  # Model crash after atomic report but before cursor.
        second = collector.execute(self.settings,self.output,self.state,self.sources,self.clock+timedelta(minutes=30))
        self.assertEqual(second['window_start'],first['window_end'])
        collector.atomic_replace(self.state,{'version':1,'project_ref':PROJECT,'cursor_end':first['window_end']})
        third = collector.execute(self.settings,self.output,self.state,self.sources,self.clock+timedelta(minutes=45))
        self.assertEqual(third['window_start'],second['window_end'])

    def test_first_failure_keeps_pending_lower_bound_for_the_retry(self):
        self.fake.db_unavailable=True
        failed=collector.execute(self.settings,self.output,self.state,self.sources,self.clock)
        self.assertFalse(failed['complete'])
        self.assertEqual(json.loads(self.state.read_text())['cursor_end'],failed['window_start'])
        self.fake.db_unavailable=False
        resumed=collector.execute(self.settings,self.output,self.state,self.sources,self.clock+timedelta(minutes=15))
        self.assertEqual(resumed['window_start'],failed['window_start'])
        self.assertEqual(json.loads(self.state.read_text())['cursor_end'],resumed['window_end'])

    def test_configured_backup_and_public_certificate_are_measured_not_invented(self):
        backups = self.root / 'backups'; backups.mkdir(mode=0o700)
        self.settings['backup'] = {'root': str(backups), 'max_age_hours': 26}
        self.settings['thresholds']['backup_failed'] = 1
        cert = self.root / 'public.pem'; cert.write_bytes(b'-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n')
        self.settings['certificates'] = [{'path': str(cert), 'warning_days': 30}]
        self.settings['thresholds']['certificate_expiring'] = 1
        expiry = (self.clock+timedelta(days=2)).strftime('%b %d %H:%M:%S %Y GMT')
        with mock.patch.object(collector.subprocess, 'run', return_value=subprocess.CompletedProcess([],0,('notAfter='+expiry+'\n').encode(),b'')) as openssl:
            report = self.collect()
        self.assertTrue(report['complete']); self.assertEqual(report['counts']['backup_failed'], 1)
        self.assertEqual(report['counts']['certificate_expiring'], 1)
        self.assertNotIn(str(cert), openssl.call_args.args[0]); self.assertIn('input', openssl.call_args.kwargs)
        cert.write_bytes(b'-----BEGIN PRIVATE KEY-----\nnever parse or log\n')
        report = self.collect()
        self.assertFalse(report['complete']); self.assertNotIn('certificate_expiring', report['counts'])

    def test_dry_run_loads_no_tokens_and_failure_emits_incomplete_sanitized_report(self):
        path = self.write_config()
        args = ['--config',str(path),'--output',str(self.output),'--state',str(self.state)]
        with mock.patch.object(cli.Sources, 'from_env') as credentials, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(args),0)
        credentials.assert_not_called(); self.assertFalse(self.output.exists())
        with mock.patch.object(cli.Sources, 'from_env',side_effect=ValueError('sbp_secret_must_not_print')), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(cli.main(args+['--run']),1)
        self.assertNotIn('sbp_secret',output.getvalue()); self.assertFalse(json.loads(self.output.read_text())['complete'])
        self.assertTrue(self.state.exists())  # Pending lower bound survives missing credentials.

    def test_tokens_private_files_and_destinations_are_constrained(self):
        token = self.root/'token'; token.write_text(MANAGEMENT); token.chmod(0o600)
        self.assertEqual(collector.token({'TOKEN_FILE':str(token)},'TOKEN'),MANAGEMENT)
        token.chmod(0o644)
        with self.assertRaises(ValueError):collector.token({'TOKEN_FILE':str(token)},'TOKEN')
        with self.assertRaises(ValueError):collector.token({'TOKEN':MANAGEMENT,'TOKEN_FILE':str(token)},'TOKEN')
        with self.assertRaises(ValueError):collector.Sources('other.example/token',MANAGEMENT,SERVICE)
        target=self.root/'outside';target.write_text('preserve');link=self.root/'symlink';link.symlink_to(target)
        with self.assertRaises(ValueError):collector.atomic_replace(link,{'must':'not replace'})
        self.assertEqual(target.read_text(),'preserve')

    def test_unimplemented_configured_source_and_unknown_threshold_are_rejected(self):
        self.settings['github']={'required':True}
        with self.assertRaises(ValueError):collector.config(self.write_config())
        self.settings.pop('github');self.settings['thresholds']['retention_failed']=1
        with self.assertRaises(ValueError):collector.config(self.write_config())

    def test_monitor_requires_actual_collection_and_sends_failure_for_missing_coverage(self):
        collector.atomic_replace(self.output, {'version':1,'observed_at':collector.iso(ops.now()),'counts':{'auth_denial':0}})
        with self.assertRaisesRegex(ValueError,'COLLECTOR_REQUIRED'):ops.security_signals(self.output,require_collection=True)
        report=self.collect();report['counts'].pop('mfa_removed');collector.atomic_replace(self.output,report)
        with mock.patch.object(monitor,'sanitized_alert',return_value={'sent':True}) as alert,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(monitor.main(['signals','--file',str(self.output),'--require-collection','--send-alert']),1)
        alert.assert_called_once_with('monitor_failed')


if __name__=='__main__':unittest.main()
