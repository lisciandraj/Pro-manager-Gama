"""No provider/network calls: operational backup, restore and monitoring contracts."""
import contextlib
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import coco_operations as ops


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT/'scripts'/filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


backup = load('coco_backup_test', 'backup-coco.py')
runner = load('coco_runner_test', 'coco-operations.py')
drill = load('coco_drill_test', 'coco-restore-drill.py')


class OpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.root.chmod(0o700)

    def bundle(self, age_hours=1, suffix='aaaaaaaa'):
        finish = datetime.now(timezone.utc)-timedelta(hours=age_hours)
        path = self.root/('backup-'+finish.strftime('%Y%m%dT%H%M%SZ')+'-'+suffix)
        path.mkdir(mode=0o700)
        artifacts = []
        for name in ('database.dump.age', 'manifest.json.age'):
            (path/name).write_bytes(b'encrypted-fixture'); (path/name).chmod(0o600)
            artifacts.append({'file':name, 'sha256':ops.file_digest(path/name)})
        ops.atomic_json(path/'COMPLETE.json', {'format':'coco-encrypted-backup','version':2,'finished_at':finish.isoformat(),'artifacts':artifacts})
        return path

    def test_completion_marker_atomic_and_never_overwritten(self):
        p=self.root/'COMPLETE.json'
        ops.atomic_json(p, {'complete':True})
        self.assertEqual(p.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(FileExistsError): ops.atomic_json(p, {'complete':False})
        self.assertEqual(json.loads(p.read_text()), {'complete':True})
        self.assertFalse((self.root/'COMPLETE.json.partial').exists())

    def test_freshness_requires_complete_verified_ciphertexts(self):
        self.assertFalse(ops.freshness(self.root,26)['healthy'])
        p=self.bundle()
        self.assertTrue(ops.freshness(self.root,26)['healthy'])
        (p/'database.dump.age').write_bytes(b'changed')
        result=ops.freshness(self.root,26)
        self.assertFalse(result['healthy']); self.assertEqual(result['incomplete_backups'],1)

    def test_old_complete_copy_is_stale(self):
        self.bundle(40)
        self.assertFalse(ops.freshness(self.root,26)['healthy'])

    def test_symlink_or_extra_content_never_valid_or_deleted(self):
        p=self.bundle()
        (p/'unknown.txt').write_text('unrelated')
        with self.assertRaises(ValueError): ops.verify_bundle(p)
        (p/'unknown.txt').unlink(); (p/'database.dump.age').unlink()
        (p/'database.dump.age').symlink_to(self.root/'outside')
        with self.assertRaises(OSError): ops.verify_bundle(p)

    def test_retention_is_approved_dry_run_and_keeps_minimum(self):
        for n in range(4):self.bundle(48+n, f'{n:08x}')
        policy=self.root/'retention.json'; policy.touch(mode=0o600); policy.write_text(json.dumps({'approved':True,'delete_after_days':1,'minimum_complete_copies':2}))
        self.assertEqual(ops.retention(self.root,policy)['eligible_copies'],2)
        self.assertEqual(len(list(self.root.glob('backup-*'))),4)
        result=ops.retention(self.root,policy,True)
        self.assertEqual(result['preserved_complete_copies'],2)
        self.assertEqual(len(list(self.root.glob('backup-*'))),2)
        policy.write_text('{"approved":false}')
        with self.assertRaises(ValueError): ops.retention(self.root,policy,True)

    def test_alert_payload_is_sanitized_and_redirect_is_refused(self):
        opener=mock.Mock(); response=mock.Mock(status=204)
        opener.open.return_value.__enter__=mock.Mock(return_value=response)
        opener.open.return_value.__exit__=mock.Mock(return_value=False)
        env={'COCO_ALERT_WEBHOOK_URL':'https://monitor.example.test/token','COCO_SERVICE_KEY':'must-not-appear'}
        self.assertTrue(ops.sanitized_alert('backup_failed',2,env,opener)['sent'])
        request=opener.open.call_args.args[0]; body=json.loads(request.data)
        self.assertEqual(set(body),{'service','event','count','time'});self.assertNotIn('must-not-appear',request.data.decode())
        with self.assertRaises(ValueError): ops.NoRedirect().redirect_request(None,None,302,'',{},'https://elsewhere.test')
        with self.assertRaises(ValueError):ops.sanitized_alert('customer_name',1,env,opener)

    def test_check_failure_exit_and_opt_in_alert(self):
        with mock.patch.object(runner,'sanitized_alert') as alert, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(['check','--root',str(self.root),'--max-age-hours','26']),1)
            alert.assert_not_called()
            self.assertEqual(runner.main(['check','--root',str(self.root),'--max-age-hours','26','--send-alert']),1)
            alert.assert_called_once_with('backup_failed')

    def test_vault_inventory_refuses_public_file_and_symlink(self):
        asset=self.root/'sri.p12';asset.write_bytes(b'fake-certificate');asset.chmod(0o600)
        inventory=self.root/'vault.json';inventory.write_text(json.dumps([{'id':'sri','path':str(asset)}]));inventory.chmod(0o600)
        self.assertEqual(backup.vault_assets(inventory)[0]['id'],'sri')
        asset.chmod(0o644)
        with self.assertRaises(ValueError):backup.vault_assets(inventory)
        asset.unlink();asset.symlink_to(self.root/'other')
        with self.assertRaises(ValueError):backup.vault_assets(inventory)

    def test_encryption_failure_never_promotes_artifact(self):
        process=mock.Mock();process.stdin=io.BytesIO();process.wait.return_value=1
        with mock.patch.object(backup.subprocess,'Popen',return_value=process):
            with self.assertRaises(RuntimeError):backup.encrypt(io.BytesIO(b'dummy'),self.root/'database.dump.age','age1dummy')
        self.assertFalse((self.root/'database.dump.age').exists())
        self.assertFalse((self.root/'COMPLETE.json').exists())

    def test_scheduled_backup_failure_alert_is_sanitized(self):
        module=mock.Mock();module.run.side_effect=ValueError('postgresql://must-not-log-secret')
        spec=mock.Mock()
        env={'COCO_BACKUP_LOCATION_ATTESTED':'off-provider','COCO_VAULT_ASSETS_FILE':'/private/inventory.json'}
        output=io.StringIO()
        with mock.patch.dict(os.environ,env),mock.patch.object(runner.importlib.util,'spec_from_file_location',return_value=spec),mock.patch.object(runner.importlib.util,'module_from_spec',return_value=module),mock.patch.object(runner,'sanitized_alert',return_value={'sent':True}) as alert,contextlib.redirect_stdout(output):
            result=runner.main(['backup','--root',str(self.root),'--run','--send-alert'])
        self.assertEqual(result,1);alert.assert_called_once_with('backup_failed')
        self.assertNotIn('must-not-log-secret',output.getvalue())
        self.assertEqual(json.loads(output.getvalue())['alert'],'sent')

    def test_backup_connection_cannot_override_project_or_tls(self):
        env={'COCO_DATABASE_URL':'postgresql://postgres:dummy@db.mknsaibrewksgomuslev.supabase.co:5432/postgres','COCO_SUPABASE_URL':'https://mknsaibrewksgomuslev.supabase.co','COCO_SERVICE_KEY':'dummy','COCO_AGE_RECIPIENT':'age1dummy'}
        self.assertEqual(backup.preflight(env),env['COCO_SUPABASE_URL'])
        for connection in [env['COCO_DATABASE_URL']+'?sslmode=disable',env['COCO_DATABASE_URL'].replace('db.mknsaibrewksgomuslev.supabase.co','example.test'),env['COCO_DATABASE_URL'].replace(':5432',':6543')]:
            with self.assertRaises(ValueError):backup.preflight({**env,'COCO_DATABASE_URL':connection})

    def test_restore_refuses_production_and_nonisolated_network(self):
        safe='postgresql://dummy@127.0.0.1:5432/coco_restore_drill'
        self.assertEqual(drill.target_guard(safe,'http://127.0.0.1:54321',{'lo'}),'http://127.0.0.1:54321')
        for db,url,interfaces in [
            ('postgresql://dummy@db.mknsaibrewksgomuslev.supabase.co/postgres','http://127.0.0.1',{'lo'}),
            ('postgresql://dummy@127.0.0.1:5432/postgres','http://127.0.0.1',{'lo'}),
            (safe,'https://mknsaibrewksgomuslev.supabase.co',{'lo'}),
            (safe,'http://127.0.0.1',{'lo','eth0'}),
            (safe+'?host=remote','http://127.0.0.1',{'lo'})]:
            with self.assertRaises(ValueError):drill.target_guard(db,url,interfaces)
        with mock.patch.dict(os.environ,{'PGSERVICE':'production','PGHOST':'production'}):
            clean=drill.isolated_env(safe);self.assertNotIn('PGSERVICE',clean);self.assertNotIn('PGHOST',clean)

    def test_restore_dry_run_only_checks_encrypted_integrity(self):
        p=self.bundle();report=self.root/'report.json'
        with mock.patch.object(drill,'restore_database') as run,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(drill.main(['--bundle',str(p),'--output',str(report)]),0)
            run.assert_not_called()
        self.assertFalse(json.loads(report.read_text())['restore_executed'])

    def test_monitor_does_not_claim_success_when_required_alert_is_unconfigured(self):
        p=self.root/'signals.json';p.write_text(json.dumps({'version':1,'observed_at':ops.now().isoformat(),'counts':{'sensitive_export':1}}))
        with mock.patch.object(runner,'sanitized_alert',return_value={'configured':False,'sent':False}),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(['signals','--file',str(p),'--send-alert']),1)

    def test_signal_monitor_refuses_stale_or_content_fields(self):
        p=self.root/'signals.json';p.write_text(json.dumps({'version':1,'observed_at':ops.now().isoformat(),'counts':{'sensitive_export':1}}))
        self.assertTrue(ops.security_signals(p)['action_required'])
        p.write_text(json.dumps({'version':1,'observed_at':ops.now().isoformat(),'counts':{'customer_email':1}}))
        with self.assertRaises(ValueError):ops.security_signals(p)
        p.write_text(json.dumps({'version':1,'observed_at':(ops.now()-timedelta(hours=10)).isoformat(),'counts':{}}))
        with self.assertRaises(ValueError):ops.security_signals(p)


if __name__ == '__main__':unittest.main()
