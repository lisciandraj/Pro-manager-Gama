"""Prepare a private OSRM host. No ERP business writes or subscription changes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
STATE = HERE.parent / '.runtime'
CHECK = ROOT / 'scripts/check-tms-road-service.mjs'
EXTRACT = 'https://download.geofabrik.de/south-america/ecuador-latest.osm.pbf'


def run(args, **options):
    result = subprocess.run(args, check=True, capture_output=True, text=True, **options)
    return result.stdout.strip()


def read_env(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        if not re.fullmatch(r'[A-Z_]+', key) or any(c.isspace() or c in "'\"$#\\" for c in value):
            raise ValueError('Invalid private environment file')
        values[key] = value
    return values


def write_private(path, values, replace=False):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or (path.exists() and not replace):
        raise ValueError('Refusing to replace an existing private configuration')
    body = '\n'.join(f'{key}={value}' for key, value in values.items()) + '\n'
    # Parse our own representation: dotenv interpolation and multiline values are forbidden.
    for value in values.values():
        if any(c.isspace() or c in "'\"$#\\" for c in str(value)):
            raise ValueError('Configuration values must not contain spaces or dotenv syntax')
    fd, name = tempfile.mkstemp(prefix='.config-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def initialize(state, host, email):
    label = r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
    if len(host) > 253 or not re.fullmatch(label + r'(?:\.' + label + r')+', host):
        raise ValueError('Use a dedicated DNS hostname, without a scheme, port or path')
    if re.fullmatch(r'[0-9.]+', host) or not re.fullmatch(r'[a-zA-Z0-9.!%+_-]+@' + label + r'(?:\.' + label + r')+', email):
        raise ValueError('Invalid DNS hostname or certificate contact')
    images = json.loads((HERE / 'images.json').read_text())
    architecture = {'x86_64': 'amd64', 'aarch64': 'arm64', 'arm64': 'arm64'}.get(platform.machine())
    if architecture not in images['osrm']:
        raise ValueError('This deployment supports Linux amd64 and arm64 hosts')
    values = dict(OSRM_IMAGE=images['osrm'][architecture]['image'], CADDY_IMAGE=images['caddy']['image'],
                  TMS_OSRM_URL='https://' + host, TMS_TLS_EMAIL=email, TMS_OSRM_TOKEN=secrets.token_hex(32),
                  TMS_OSRM_DATA_DIR='', TMS_ROAD_DATA_VERSION='', TMS_OSRM_MEMORY='4g', TMS_OSRM_CPUS='2')
    write_private(state / 'server.env', values)
    return {'initialized': True, 'architecture': architecture, 'next': 'prepare a graph; credentials are in the private server.env file'}


def fixture(destination):
    destination.mkdir(parents=True, exist_ok=False)
    points = [[round(-78.52 + col * .002, 6), round(-.22 + row * .002, 6)] for row in range(10) for col in range(12)]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<osm version="0.6" generator="Coco isolated routing test">']
    for index, (lng, lat) in enumerate(points):
        lines.append(f'<node id="{index + 1}" version="1" lon="{lng}" lat="{lat}"/>')
    ways = []
    for row in range(10):
        ways.append(([row * 12 + col + 1 for col in range(12)], 'yes' if row % 2 == 0 else '-1'))
    for col in range(12):
        ways.append(([row * 12 + col + 1 for row in range(10)], 'no'))
    for index, (nodes, direction) in enumerate(ways):
        lines.append(f'<way id="{1000 + index}" version="1">' + ''.join(f'<nd ref="{n}"/>' for n in nodes)
                     + f'<tag k="highway" v="residential"/><tag k="maxspeed" v="30"/><tag k="oneway" v="{direction}"/></way>')
    (destination / 'network.osm').write_text('\n'.join(lines + ['</osm>']) + '\n')
    (destination / 'points.json').write_text(json.dumps(points) + '\n')
    return {'fixture': True, 'locations': len(points)}


def download_ecuador(state):
    directory = state / 'downloads'
    directory.mkdir(parents=True, exist_ok=True)
    # The provider's checksum detects incomplete/corrupt downloads; HTTPS authenticates origin.
    with urllib.request.urlopen(EXTRACT + '.md5', timeout=30) as response:
        checksum = response.read(1024).decode().split()[0]
    if not re.fullmatch(r'[a-fA-F0-9]{32}', checksum):
        raise ValueError('Invalid extract checksum')
    target = directory / ('ecuador-' + checksum.lower() + '.osm.pbf')
    if target.exists():
        with target.open('rb') as existing:
            valid = hashlib.file_digest(existing, 'md5').hexdigest() == checksum.lower()
        if valid:
            return target
        raise ValueError('Existing extract does not match the provider checksum')
    fd, name = tempfile.mkstemp(prefix='.download-', dir=directory)
    digest, size = hashlib.md5(), 0
    try:
        with os.fdopen(fd, 'wb') as output, urllib.request.urlopen(EXTRACT, timeout=60) as response:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 2 * 1024 ** 3:
                    raise ValueError('Extract exceeds the reviewed 2 GiB download limit')
                output.write(chunk)
                digest.update(chunk)
        if digest.hexdigest() != checksum.lower():
            raise ValueError('Extract checksum mismatch; no graph was replaced')
        os.replace(name, target)
    finally:
        Path(name).unlink(missing_ok=True)
    return target


def wait_for_http(base):
    for _ in range(50):
        try:
            with urllib.request.urlopen(base, timeout=1):
                return
        except urllib.error.HTTPError as error:
            if error.code < 500:
                return
        except (OSError, TimeoutError):
            pass
        time.sleep(1)
    raise ValueError('Isolated routing process did not become ready')


def prepare(state, source, points=None, sizes=None, memory='4g'):
    values = read_env(state / 'server.env')
    if not re.fullmatch(r'[1-9][0-9]*[gm]', memory):
        raise ValueError('Use an explicit Docker memory bound, for example 4g')
    if source.suffix not in ['.osm', '.pbf']:
        raise ValueError('Input must be an OSM XML or PBF file')
    with source.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    image = values['OSRM_IMAGE']
    if not re.fullmatch(r'ghcr\.io/project-osrm/osrm-backend:[a-zA-Z0-9_.-]+@sha256:[a-f0-9]{64}', image):
        raise ValueError('A reviewed, immutable OSRM image is required')
    version = 'ch-' + hashlib.sha256((digest + '|' + image + '|car').encode()).hexdigest()[:20]
    datasets = state / 'datasets'
    datasets.mkdir(parents=True, exist_ok=True)
    destination = datasets / version
    if destination.exists():
        raise ValueError('This immutable dataset already exists; use its existing environment and validation result')
    temporary = tempfile.TemporaryDirectory(prefix='.preparing-', dir=datasets)
    staging = Path(temporary.name)
    try:
        staging.chmod(0o755)
        name = 'network.osm' if source.suffix == '.osm' else 'network.osm.pbf'
        shutil.copyfile(source, staging / name)
        common = ['docker', 'run', '--rm', '--network', 'none', '--user', f'{os.getuid()}:{os.getgid()}',
                  '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--pids-limit', '512',
                  '--cpus', '2', '--memory', memory, '--memory-swap', memory, '--log-driver', 'none',
                  '--mount', f'type=bind,src={staging},dst=/data', image]
        # Fresh staging only: a failed preparation cannot overwrite the running graph or credentials.
        run(common + ['osrm-extract', '--threads', '2', '--verbosity', 'WARNING', '-p', '/opt/car.lua', '/data/' + name])
        run(common + ['osrm-contract', '--threads', '2', '--verbosity', 'WARNING', '/data/network.osrm'])
        for file in staging.iterdir():
            if file.is_file():
                file.chmod(0o644)
        container = 'coco-tms-check-' + uuid.uuid4().hex[:12]
        try:
            run(['docker', 'run', '--detach', '--rm', '--name', container, '--user', '65532:65532', '--read-only',
                 '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--pids-limit', '256', '--cpus', '2',
                 '--memory', memory, '--log-driver', 'none', '--publish', '127.0.0.1::5000',
                 '--mount', f'type=bind,src={staging},dst=/data,readonly', image,
                 'osrm-routed', '--algorithm', 'ch', '--max-table-size', '128', '--threads', '2', '--verbosity', 'WARNING', '/data/network.osrm'])
            address = run(['docker', 'port', container, '5000/tcp'])
            if not re.fullmatch(r'127\.0\.0\.1:[0-9]+', address):
                raise ValueError('Candidate routing process was not restricted to loopback')
            wait_for_http('http://' + address)
            arguments = ['node', str(CHECK), '--loopback', '--raw-osrm']
            if points:
                arguments += ['--points', str(points)]
            if sizes:
                arguments += ['--sizes', sizes]
            result = json.loads(run(arguments, env={**os.environ, 'TMS_OSRM_URL': 'http://' + address, 'TMS_ROAD_DATA_VERSION': version}))
        finally:
            subprocess.run(['docker', 'rm', '--force', container], capture_output=True, check=False)
        manifest = dict(version=version, algorithm='ch', profile='car', osrm_image=image, input_sha256=digest,
                        prepared_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), validation=result)
        (staging / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        staging.rename(destination)
        values.update(TMS_OSRM_DATA_DIR=str(destination.resolve()), TMS_ROAD_DATA_VERSION=version)
        write_private(state / 'server.env', values, replace=True)
        # Downloaded source is reproducible and not needed by the read-only routing process.
        (destination / name).unlink()
        return manifest
    finally:
        temporary.cleanup()


def check_public(state):
    values = read_env(state / 'server.env')
    result = json.loads(run(['node', str(CHECK)], env={**os.environ, **values}))
    export = {key: values[key] for key in ['TMS_OSRM_URL', 'TMS_OSRM_TOKEN', 'TMS_ROAD_DATA_VERSION']}
    write_private(state / 'supabase.env', export, replace=True)
    return {**result, 'secrets_file_ready': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=STATE)
    commands = parser.add_subparsers(dest='command', required=True)
    init = commands.add_parser('init')
    init.add_argument('--host', required=True)
    init.add_argument('--email', required=True)
    sample = commands.add_parser('fixture')
    sample.add_argument('--destination', type=Path, required=True)
    build = commands.add_parser('prepare')
    inputs = build.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--input', type=Path)
    inputs.add_argument('--ecuador', action='store_true')
    build.add_argument('--points', type=Path)
    build.add_argument('--sizes')
    build.add_argument('--memory', default='4g')
    commands.add_parser('check')
    args = parser.parse_args()
    args.state_dir = args.state_dir.resolve()
    if args.command == 'init':
        result = initialize(args.state_dir, args.host, args.email)
    elif args.command == 'fixture':
        result = fixture(args.destination)
    elif args.command == 'prepare':
        source = download_ecuador(args.state_dir) if args.ecuador else args.input
        result = prepare(args.state_dir, source, args.points, args.sizes, args.memory)
    else:
        result = check_public(args.state_dir)
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, urllib.error.URLError):
        # Never copy subprocess output, environment, bearer tokens or coordinate URLs to logs.
        print(json.dumps({'ok': False, 'error': 'ROUTING_PREPARATION_FAILED'}))
        raise SystemExit(1)
