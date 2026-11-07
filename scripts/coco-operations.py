#!/usr/bin/env python3
"""Backup scheduling/supervision and incident rehearsal. No live call in dry-run."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import uuid
from coco_operations import EVENTS, atomic_json, freshness, now, private_directory, retention, sanitized_alert, security_signals
from coco_drive_backup import DriveClient, drive_freshness, encrypted_plan, folder_id, reconstruct_marker, upload_bundle, write_receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    backup = sub.add_parser('backup'); backup.add_argument('--root', type=Path, required=True); backup.add_argument('--run', action='store_true')
    backup.add_argument('--drive', action='store_true', help='Require verified Google Drive delivery before success')
    upload = sub.add_parser('drive-upload'); upload.add_argument('--bundle', type=Path, required=True); upload.add_argument('--run', action='store_true')
    recover = sub.add_parser('drive-recover-marker'); recover.add_argument('--bundle', type=Path, required=True); recover.add_argument('--folder-metadata', type=Path, required=True); recover.add_argument('--apply', action='store_true')
    check = sub.add_parser('check'); check.add_argument('--root', type=Path, required=True); check.add_argument('--max-age-hours', type=float, required=True)
    check.add_argument('--drive', action='store_true', help='Also require a recent receipt of verified Drive delivery')
    keep = sub.add_parser('retention'); keep.add_argument('--root', type=Path, required=True); keep.add_argument('--policy', type=Path, required=True); keep.add_argument('--apply', action='store_true')
    alert = sub.add_parser('alert'); alert.add_argument('--event', choices=sorted(EVENTS), required=True)
    signals = sub.add_parser('signals'); signals.add_argument('--file', type=Path, required=True)
    incident = sub.add_parser('incident'); incident.add_argument('--scenario', choices=['account-compromise', 'backup-failure', 'data-exposure'], required=True); incident.add_argument('--output', type=Path, required=True)
    for command in [backup, upload, check, keep, signals, alert]:
        command.add_argument('--send-alert', action='store_true', help='Deliver sanitized event to configured webhook; disabled unless explicit')
    args = parser.parse_args(argv)
    try:
        if args.action == 'backup':
            private_directory(args.root)
            if not args.run:
                result = {'event': 'backup_preflight', 'mode': 'dry-run', 'production_access': False,
                          'vault_inventory_configured': bool(os.getenv('COCO_VAULT_ASSETS_FILE')),
                          'drive_required': args.drive, 'drive_folder_configured': bool(os.getenv('COCO_DRIVE_FOLDER_ID')),
                          'drive_token_configured': bool(os.getenv('COCO_DRIVE_ACCESS_TOKEN') or os.getenv('COCO_DRIVE_TOKEN_FILE'))}
            else:
                if os.getenv('COCO_BACKUP_LOCATION_ATTESTED') != 'off-provider':
                    raise ValueError('OFF_PROVIDER_LOCATION_ATTESTATION_REQUIRED')
                if not os.getenv('COCO_VAULT_ASSETS_FILE'):
                    raise ValueError('VAULT_INVENTORY_REQUIRED_FOR_SCHEDULED_BACKUP')
                drive = DriveClient.from_env() if args.drive else None
                spec = importlib.util.spec_from_file_location('coco_backup', Path(__file__).with_name('backup-coco.py'))
                module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
                destination = args.root / ('backup-' + now().strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
                module.run(destination, report=False)
                result = {'event': 'backup_completed', 'complete': True, 'finished_at': now().isoformat()}
                if drive is not None:
                    delivery = upload_bundle(destination, drive)
                    write_receipt(args.root, destination, delivery)
                    result['drive'] = delivery
        elif args.action == 'drive-upload':
            if args.run:
                result = upload_bundle(args.bundle, DriveClient.from_env())
                write_receipt(args.bundle.parent, args.bundle, result)
            else:
                _, plan = encrypted_plan(args.bundle)
                result = {'event': 'drive_backup_preflight', 'mode': 'dry-run', 'production_access': False,
                          'drive_folder_configured': bool(os.getenv('COCO_DRIVE_FOLDER_ID')), **plan}
        elif args.action == 'drive-recover-marker':
            result = reconstruct_marker(args.bundle, args.folder_metadata, folder_id(), args.apply)
        elif args.action == 'check':
            result = drive_freshness(args.root, args.max_age_hours, folder_id()) if args.drive else freshness(args.root, args.max_age_hours)
            if not result['healthy']:
                if args.send_alert: sanitized_alert('backup_failed')
                print(json.dumps(result)); return 1
        elif args.action == 'retention':
            result = retention(args.root, args.policy, args.apply)
        elif args.action == 'alert':
            result = {'event': args.event, 'mode': 'apply' if args.send_alert else 'dry-run', 'delivery': sanitized_alert(args.event) if args.send_alert else {'sent': False}}
            if args.send_alert and not result['delivery']['sent']:
                print(json.dumps(result)); return 1
        elif args.action == 'signals':
            result = security_signals(args.file)
            if args.send_alert:
                deliveries = []
                for event, count in result['counts'].items():
                    if count: deliveries.append({'event': event, **sanitized_alert(event, count)})
                result['alert_delivery'] = deliveries
                if any(not delivery['sent'] for delivery in deliveries):
                    print(json.dumps(result)); return 1
        else:
            result = {'event': 'incident_rehearsal', 'scenario': args.scenario, 'mode': 'dry-run',
                      'production_access': False, 'notification_sent': False, 'started_at': now().isoformat(),
                      'checks': {'named_owner': 'operator_required', 'containment': 'simulate_only',
                                 'session_revocation': 'recipe_in_runbook', 'restore': 'isolated_drill_required',
                                 'notification_obligations': 'qualified_owner_decision_required'},
                      'status': 'rehearsal_template_not_executed_incident'}
            atomic_json(args.output, result)
        print(json.dumps(result)); return 0
    except Exception as error:
        event = 'retention_failed' if args.action == 'retention' else 'monitor_failed' if args.action == 'signals' else 'backup_failed'
        alert = 'not_requested'
        if getattr(args, 'send_alert', False):
            try: alert = 'sent' if sanitized_alert(event)['sent'] else 'not_configured'
            except Exception: alert = 'delivery_failed'
        print(json.dumps({'event': args.action + '_failed', 'code': type(error).__name__, 'alert': alert})); return 1


if __name__ == '__main__':
    raise SystemExit(main())
