#!/usr/bin/env python3
"""Collect bounded aggregate security signals; dry-run never loads credentials."""
import argparse
import json
from pathlib import Path
from coco_operations import now
from coco_security_collector import CollectionBusy, REMOTE_SOURCES, Sources, atomic_replace, config, execute, iso


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args(argv)
    try:
        settings = config(args.config)
        if not args.run:
            print(json.dumps({'event': 'security_collection_preflight', 'mode': 'dry-run', 'production_access': False,
                              'required_sources': list(REMOTE_SOURCES), 'backup_configured': settings.get('backup') is not None,
                              'public_certificates_configured': len(settings.get('certificates', []))})); return 0
        report = execute(settings, args.output, args.state, lambda: Sources.from_env(settings['project_ref']))
        print(json.dumps({'event': 'security_collection_completed' if report['complete'] else 'security_collection_incomplete',
                          'complete': report['complete'], 'coverage': report['coverage'], 'observed_at': report['observed_at']}))
        return 0 if report['complete'] else 1
    except Exception as error:
        if args.run and not isinstance(error, CollectionBusy):
            try:
                atomic_replace(args.output, {'version': 2, 'observed_at': iso(now()), 'complete': False,
                    'coverage': {name: 'unavailable' for name in REMOTE_SOURCES}, 'counts': {'monitor_failed': 1},
                    'alert_counts': {'monitor_failed': 1}, 'metrics': {}})
            except Exception:
                pass
        print(json.dumps({'event': 'security_collection_failed', 'complete': False, 'code': type(error).__name__})); return 1


if __name__ == '__main__':
    raise SystemExit(main())
