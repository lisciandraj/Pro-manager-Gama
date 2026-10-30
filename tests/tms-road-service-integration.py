"""Exercise the actual pinned OSRM and HTTPS-proxy configuration on an isolated graph.

Requires Docker Compose >= 2.24.4. The CI override exposes HTTP on loopback only;
production compose retains HTTPS and exposes no OSRM port.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEPLOY = ROOT / 'services/tms-routing/deploy'
spec = importlib.util.spec_from_file_location('coco_road_prepare', DEPLOY / 'prepare.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
stage = 'initialize'


def command(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def main():
    global stage
    with tempfile.TemporaryDirectory(prefix='coco-road-ci-') as directory:
        state = Path(directory)
        fixture = state / 'fixture'
        prepare.fixture(fixture)
        prepare.initialize(state, 'roads.example.invalid', 'test@example.invalid')
        stage = 'prepare-real-osrm-graph'
        manifest = prepare.prepare(state, fixture / 'network.osm', fixture / 'points.json', '20,50,100', '1g')
        values = prepare.read_env(state / 'server.env')
        override = state / 'ci-only.yml'
        # No hostname matcher: the checker reaches the published 127.0.0.1 port,
        # rather than sending Host: localhost to the container.
        override.write_text("services:\n  caddy:\n    environment:\n      TMS_OSRM_SITE: ':80'\n    ports: !override\n      - 127.0.0.1::80\n")
        project = 'coco-road-ci-' + uuid.uuid4().hex[:12]
        compose = ['docker', 'compose', '--project-name', project, '--env-file', str(state / 'server.env'),
                   '-f', str(DEPLOY / 'compose.yml'), '-f', str(override)]
        try:
            stage = 'validate-production-proxy-config'
            try:
                command(compose + ['run', '--rm', '--no-deps', '-e', 'TMS_OSRM_SITE=https://roads.example.invalid',
                                   'caddy', 'caddy', 'validate', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile'])
            except subprocess.CalledProcessError as error:
                # Configuration-only validation receives no coordinate requests.
                safe = (error.stdout + error.stderr).replace(values['TMS_OSRM_TOKEN'], '[REDACTED]')
                print(json.dumps({'proxy_config_diagnostic': safe[-1800:]}))
                raise
            stage = 'start-proxy-and-internal-osrm'
            command(compose + ['up', '--detach'])
            address = command(compose + ['port', 'caddy', '80'])
            assert address.startswith('127.0.0.1:')
            base = 'http://' + address
            samples = json.loads((fixture / 'points.json').read_text())[:2]
            url = base + '/table/v1/driving/' + ';'.join(','.join(map(str, p)) for p in samples)
            stage = 'wait-for-private-proxy'
            for _ in range(30):
                try:
                    request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + values['TMS_OSRM_TOKEN']})
                    with urllib.request.urlopen(request, timeout=1) as response:
                        if json.load(response).get('code') == 'Ok':
                            break
                except (OSError, urllib.error.HTTPError, ValueError):
                    pass
                time.sleep(1)
            else:
                raise ValueError('PROXY_NOT_READY')
            stage = 'authenticated-20-50-100-matrices'
            result = json.loads(command(['node', str(ROOT / 'scripts/check-tms-road-service.mjs'), '--loopback',
                                         '--points', str(fixture / 'points.json'), '--sizes', '20,50,100'],
                                        env={**os.environ, **values, 'TMS_OSRM_URL': base}))
            stage = 'container-privacy-and-isolation'
            ids = command(compose + ['ps', '--quiet']).splitlines()
            inspected = json.loads(command(['docker', 'inspect', *ids]))
            for item in inspected:
                config = item['HostConfig']
                assert config['ReadonlyRootfs']
                assert config['LogConfig']['Type'] == 'none'
                assert 'ALL' in config['CapDrop']
                if item['Config']['Labels']['com.docker.compose.service'] == 'osrm':
                    assert not config.get('PortBindings')
            output = {'ok': True, 'dataset': 'synthetic OSM grid; no customer data or live Quito traffic',
                      'images': {'osrm': values['OSRM_IMAGE'], 'caddy': values['CADDY_IMAGE']},
                      'graph_version': manifest['version'], 'raw_osrm': manifest['validation']['results'],
                      'private_proxy': result, 'read_only': True, 'request_logging': False, 'osrm_port_public': False}
            destination = ROOT / 'test-results/tms-road-service.json'
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(json.dumps(output, indent=2) + '\n')
            print(json.dumps(output))
        finally:
            subprocess.run(compose + ['down', '--volumes'], capture_output=True, check=False)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never dump a docker inspect/environment, URL, raw response or subprocess output.
        print(json.dumps({'ok': False, 'stage': stage, 'error': 'PRIVATE_OSRM_CONTAINER_TEST_FAILED'}))
        raise SystemExit(1)
