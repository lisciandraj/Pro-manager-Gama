"""Scheduled consultations reuse the Edge Function; no document is resent here."""
import asyncio
import logging
import os
from urllib.parse import urlsplit
from contextlib import asynccontextmanager
import requests

log = logging.getLogger('coco.sri.reconcile')


def configuration():
    url = os.getenv('SRI_SUPABASE_URL', '').rstrip('/')
    key = os.getenv('SRI_SUPABASE_PUBLISHABLE_KEY', '')
    capability = os.getenv('SRI_RECONCILE_TOKEN', '')
    parsed = urlsplit(url)
    if not key or len(capability) != 64 or any(c not in '0123456789abcdefABCDEF' for c in capability) or parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path:
        return None
    interval = max(60, min(3600, int(os.getenv('SRI_RECONCILE_INTERVAL', '60'))))
    return url, key, interval, capability


def reconcile_once(session=requests):
    cfg = configuration()
    if not cfg:
        return {'enabled': False, 'consulted': 0}
    url, key, _, capability = cfg
    result = session.post(url + '/functions/v1/gama-sri',
                          headers={'Authorization': 'Bearer ' + key, 'apikey': key,
                                   'x-coco-sri-reconcile': capability},
                          json={'action': 'refresh_pending'}, timeout=55, allow_redirects=False)
    result.raise_for_status()
    data = result.json()
    if not isinstance(data, dict) or data.get('consulted') not in (0, 1):
        raise ValueError('SRI_RECONCILE_INVALID_RESPONSE')
    return {'enabled': True, 'consulted': data['consulted'], 'status': data.get('status'), 'error': data.get('error')}


async def run(stop):
    cfg = configuration()
    if not cfg:
        return
    while not stop.is_set():
        try:
            await asyncio.to_thread(reconcile_once)
        except Exception:
            # Never log the request, JWT, response content, credentials or PII.
            log.warning('SRI_RECONCILE_RETRY_PENDING')
        try:
            await asyncio.wait_for(stop.wait(), timeout=cfg[2])
        except asyncio.TimeoutError:
            pass


@asynccontextmanager
async def lifespan(app):
    stop = asyncio.Event()
    task = asyncio.create_task(run(stop))
    try:
        yield
    finally:
        stop.set()
        await task
