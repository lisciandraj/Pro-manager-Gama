#!/usr/bin/env python3
"""Backup scheduling/supervision and incident rehearsal. No live call in dry-run."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import uuid
from coco_operations import EVENTS, atomic_json, freshness, now, private_directory, retention, sanitized_alert, security_signals


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    backup = sub.add_parser('backup'); backup.add_argument('--root', type=Path, required=True); backup.add_argument('--run', action='store_true')
    check = sub.add_parser('check'); check.add_argument('--root', type=Path, required=True); check.add_argument('--max-age-hours', type=float, required=True)
    keep = sub.add_parser('retention'); keep.add_argument('--root', type=Path, required=True); keep.add_argument('--policy', type=Path, required=True); keep.add_argument('--apply', action='store_true')
    alert = sub.add_parser('alert'); alert.add_argument('--event', choices=sorted(EVENTS), required=True)
    signals = sub.add_parser('signals'); signals.add_argument('--file', type=Path, required=True)
    incident = sub.add_parser('incident'); incident.add_argument('--scenario', choices=['account-compromise', 'backup-failure', 'data-exposure'], required=True); incident.add_argument('--output', type=Path, required=True)
    for command in [backup, check, keep, signals, alert]:
        command.add_argument('--send-alert', action='store_true', help='Deliver sanitized event to configured webhook; disabled unless explicit')
    args = parser.parse_args(argv)
    try:
        if args.action == 'backup':
            private_directory(args.root)
            if not args.run:
                result = {'event': 'backup_preflight', 'mode': 'dry-run', 'production_access': False,
                          'vault_inventory_configured': bool(os.getenv('COCO_VAULT_ASSETS_FILE'))}
            else:
                if os.getenv('COCO_BACKUP_LOCATION_ATTESTED') != 'off-provider':
                    raise ValueError('OFF_PROVIDER_LOCATION_ATTESTATION_REQUIRED')
                if not os.getenv('COCO_VAULT_ASSETS_FILE'):
                    raise ValueError('VAULT_INVENTORY_REQUIRED_FOR_SCHEDULED_BACKUP')
                spec = importlib.util.spec_from_file_location('coco_backup', Path(__file__).with_name('backup-coco.py'))
                module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
                destination = args.root / ('backup-' + now().strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
                module.run(destination)
                result = {'event': 'backup_completed', 'complete': True, 'finished_at': now().isoformat()}
        elif args.action == 'check':
            result = freshness(args.root, args.max_age_hours)
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
