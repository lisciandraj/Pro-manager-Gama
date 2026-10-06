import asyncio
import hashlib
import hmac
import json
import os
import unittest
from unittest.mock import patch
from services.sri.api import app


async def post(chunks, signature='invalid', headers=None):
    messages = []
    parts = iter(chunks)
    async def receive():
        try:
            chunk = next(parts)
            return {'type': 'http.request', 'body': chunk, 'more_body': True}
        except StopIteration:
            return {'type': 'http.request', 'body': b'', 'more_body': False}
    async def send(message):
        messages.append(message)
    scope = {'type': 'http', 'asgi': {'version': '3.0'}, 'http_version': '1.1',
             'method': 'POST', 'scheme': 'https', 'path': '/execute', 'raw_path': b'/execute',
             'query_string': b'', 'server': ('private.invalid', 443), 'client': ('127.0.0.1', 1234),
             'headers': [(b'x-sri-signature', signature.encode()), *(headers or [])]}
    with patch.dict(os.environ, {'SRI_WORKER_SECRET': 'fixture-secret'}, clear=True):
        await app(scope, receive, send)
    return next(m['status'] for m in messages if m['type'] == 'http.response.start')


class SriHttpBoundaryTest(unittest.TestCase):
    def test_oversize_stream_and_content_length_rejected_before_processing(self):
        self.assertEqual(asyncio.run(post([b'x' * 1_000_001, b'x' * 1_000_001])), 413)
        self.assertEqual(asyncio.run(post([b'{}'], headers=[(b'content-length', b'2000001')])), 413)

    def test_hmac_uses_the_exact_bounded_body(self):
        self.assertEqual(asyncio.run(post([b'{"action":"status"}'])), 401)
        body = json.dumps({'action': 'status'}).encode()
        signature = hmac.new(b'fixture-secret', body, hashlib.sha256).hexdigest()
        self.assertEqual(asyncio.run(post([body[:5], body[5:]], signature)), 200)


if __name__ == '__main__':
    unittest.main()
