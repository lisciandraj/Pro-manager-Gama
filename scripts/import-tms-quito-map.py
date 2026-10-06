#!/usr/bin/env python3
"""Prepare a local Quito street snapshot; never called by the app or normal build.

Run with --download once, then rebuild from the cached municipal responses offline.
Geometry is simplified within 2 m and quantized to 1e-5 degree (about 1.1 m).
The packed unsigned varints contain name, road class, vertex count and zigzag
coordinate deltas. No client locations, cadastral owners or personal data are read.
"""
import argparse
import base64
import concurrent.futures
import gzip
import json
import math
import pathlib
import time
import urllib.parse
import urllib.request
from collections import Counter

SOURCE = 'https://geoquito.quito.gob.ec/server/rest/services/web_image_dmdu/ap030_via_l/MapServer/0'
FIELDS = 'FID,nam,catg_via,tipo,typ,fuente,componente'
ORIGIN = [-79, 0]
SCALE = 100000


def request(params):
    url = SOURCE + '/query?' + urllib.parse.urlencode({'f': 'json', **params})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=45) as response:
                data = json.load(response)
            if data.get('error') or data.get('exceededTransferLimit'):
                raise ValueError('Municipal query incomplete: ' + str(data.get('error')))
            return data
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1)


def simplify(points, tolerance=0.000018):
    """Iterative Ramer-Douglas-Peucker in the equatorial degree coordinates."""
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        ax, ay = points[first]
        bx, by = points[last]
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        furthest, distance = None, tolerance * tolerance
        for index in range(first + 1, last):
            px, py = points[index]
            ratio = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length)) if length else 0
            squared = (px - ax - ratio * dx) ** 2 + (py - ay - ratio * dy) ** 2
            if squared > distance:
                furthest, distance = index, squared
        if furthest is not None:
            keep.add(furthest)
            stack.extend([(first, furthest), (furthest, last)])
    return [points[index] for index in sorted(keep)]


def uint(buffer, value):
    while value >= 128:
        buffer.append((value & 127) | 128)
        value >>= 7
    buffer.append(value)


def zigzag(value):
    return value * 2 if value >= 0 else -value * 2 - 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--cache', default='.build/quito-map-snapshot')
    parser.add_argument('--output', default='src/features/transport/quito-map-data.js')
    args = parser.parse_args()
    cache = pathlib.Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    ids_file = cache / 'ids.json'
    if not ids_file.exists():
        if not args.download:
            raise SystemExit('Snapshot cache missing; run once with --download.')
        ids_file.write_text(json.dumps(request({'where': '1=1', 'returnIdsOnly': 'true'})))
    ids = sorted(json.loads(ids_file.read_text())['objectIds'])
    if len(ids) != len(set(ids)) or len(ids) < 10000:
        raise ValueError('Unexpected municipal road inventory')
    groups = [ids[start:start + 800] for start in range(0, len(ids), 800)]

    def batch(pair):
        index, wanted = pair
        filename = cache / ('roads-%03d.json' % index)
        if not filename.exists():
            if not args.download:
                raise ValueError('Missing cached batch ' + str(filename))
            data = request({'objectIds': ','.join(map(str, wanted)), 'outFields': FIELDS,
                            'outSR': '4326', 'geometryPrecision': '6', 'returnGeometry': 'true'})
            filename.write_text(json.dumps(data, ensure_ascii=False))
        data = json.loads(filename.read_text())
        features = data.get('features', [])
        if sorted(feature['attributes']['FID'] for feature in features) != wanted:
            raise ValueError('Road batch does not match its requested IDs: ' + str(index))
        print('Road batch %d/%d complete' % (index + 1, len(groups)), flush=True)
        return features

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        features = [feature for batch_features in pool.map(batch, enumerate(groups)) for feature in batch_features]
    features.sort(key=lambda feature: feature['attributes']['FID'])
    sources = Counter(feature['attributes'].get('fuente') or 'Unspecified' for feature in features)
    if any('openstreetmap' in source.lower() or 'osm' == source.lower() for source in sources):
        raise ValueError('Unexpected OpenStreetMap provenance')

    names, name_ids, roads, all_points = [''], {'': 0}, [], []
    categories = Counter()
    raw_vertices = 0
    for feature in features:
        attrs = feature['attributes']
        category = (attrs.get('catg_via') or '').strip()
        categories[category] += 1
        rank = {'Expresa': 0, 'Semi-expresa': 0, 'Arterial': 1, 'Colectora': 2}.get(category, 3)
        if (attrs.get('typ') or '').lower() in ['escalinata', 'peatonal', 'sendero']:
            rank = 4
        name = (attrs.get('nam') or '').strip()
        if name.upper() in ['S/N', 'SIN NOMBRE', 'N/A', 'NO APLICA', 'DESCONOCIDO', 'N/D']:
            name = ''
        if name:
            name = name.title()
            if (attrs.get('typ') or '').lower() == 'avenida':
                name = 'Av. ' + name
        if name not in name_ids:
            name_ids[name] = len(names)
            names.append(name)
        for line in feature.get('geometry', {}).get('paths', []):
            points = [coordinate[:2] for coordinate in line]
            raw_vertices += len(points)
            if len(points) < 2:
                continue
            if any(not math.isfinite(value) for point in points for value in point):
                raise ValueError('Nonfinite coordinate')
            if any(not (-81 <= lng <= -75 and -4 <= lat <= 1) for lng, lat in points):
                raise ValueError('Invalid WGS84 Ecuador geometry')
            quantized = []
            for lng, lat in simplify(points):
                point = [round((lng - ORIGIN[0]) * SCALE), round((lat - ORIGIN[1]) * SCALE)]
                if not quantized or point != quantized[-1]:
                    quantized.append(point)
            if len(quantized) < 2:
                continue
            roads.append([name_ids[name], rank, quantized])
            all_points.extend(quantized)
    packed = bytearray()
    for name, rank, points in roads:
        for value in [name, rank, len(points)]:
            uint(packed, value)
        previous = [0, 0]
        for point in points:
            for dimension in [0, 1]:
                uint(packed, zigzag(point[dimension] - previous[dimension]))
            previous = point
    xs, ys = zip(*all_points)
    bounds = [min(xs) / SCALE + ORIGIN[0], min(ys) / SCALE + ORIGIN[1],
              max(xs) / SCALE + ORIGIN[0], max(ys) / SCALE + ORIGIN[1]]
    data = {'source': SOURCE, 'snapshot': '2026-10-06', 'origin': ORIGIN, 'scale': SCALE,
            'bounds': bounds, 'count': len(roads), 'names': names,
            'packed': base64.b64encode(packed).decode('ascii')}
    output = pathlib.Path(args.output)
    output.write_text('/* Local street snapshot: Municipio del Distrito Metropolitano de Quito.\n'
                      ' * GeoQuito / IGM / EPMMOP / PUGS. Preparation: scripts/import-tms-quito-map.py.\n'
                      ' * Provenance and permitted use: docs/tms-map-data.md. No runtime API. */\n'
                      '(function(){"use strict";window.CocoQuitoMapData=' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';})();\n')
    report = {'features': len(features), 'roads': len(roads), 'raw_vertices': raw_vertices,
              'vertices': len(all_points), 'names': len(names), 'bounds': bounds,
              'bytes': output.stat().st_size, 'gzip_bytes': len(gzip.compress(output.read_bytes())),
              'sources': dict(sources), 'categories': dict(categories)}
    (cache / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
