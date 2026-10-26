#!/usr/bin/env python3
"""Read-only check of the source revision and the assets actually served by Pages."""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url', default='https://lisciandraj.github.io/Pro-manager-Gama/')
parser.add_argument('--ref', default='HEAD', help='Git revision whose generated assets must match')
parser.add_argument('--commit', required=True, help='Expected production source commit')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
base = args.url.rstrip('/') + '/'


def fetch(path):
    request = urllib.request.Request(urllib.parse.urljoin(base, path), headers={'Cache-Control': 'no-cache'})
    with urllib.request.urlopen(request, timeout=25) as response:
        return response.read()


def git_bytes(name):
    return subprocess.check_output(['git', 'show', f'{args.ref}:{name}'], cwd=root, stderr=subprocess.DEVNULL)


report = {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'url': base,
          'expected_commit': args.commit, 'git_ref': args.ref, 'assets': []}
try:
    report['build'] = json.loads(fetch('coco-build.json'))
    html = fetch('').decode('utf-8')
    manifest_path = re.search(r'src=["\']([^"\']*architect-assets\.js[^"\']*)["\']', html).group(1)
    manifest = fetch(manifest_path).decode('utf-8')
    assets = json.loads(re.search(r'window\.ArcAssets\s*=\s*(\{.*?\});', manifest, re.S).group(1))
    names = ['architect-finance-controls.js', 'coco-modules.js',
             'coco-accounting-configuration.js', 'gama-accounting.js', 'gama-payments.js',
             'gama-i18n-catalog.js', 'gama-i18n-server.js', 'gama-i18n-fr.js', 'gama-i18n-en.js']
    try:
        git_bytes('coco-accounting-earnings.js')
        names.append('coco-accounting-earnings.js')
    except subprocess.CalledProcessError:
        pass
    for name in names:
        served = fetch(assets[name])
        expected = git_bytes(name)
        report['assets'].append({'name': name, 'served_url': urllib.parse.urljoin(base, assets[name]),
                                 'bytes': len(served), 'sha256': hashlib.sha256(served).hexdigest(),
                                 'matches_git': served == expected})
    report['ok'] = report['build'].get('commit') == args.commit and all(row['matches_git'] for row in report['assets'])
except (OSError, ValueError, KeyError, AttributeError, subprocess.CalledProcessError) as error:
    report.update(ok=False, error=str(error))
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(0 if report['ok'] else 2)
