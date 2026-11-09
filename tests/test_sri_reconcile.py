import os
import unittest
from unittest.mock import patch
from services.sri.reconcile import configuration, reconcile_once

class Response:
    def raise_for_status(self): pass
    def json(self): return {'consulted': 1, 'status': 'processing'}

class SriReconcileTest(unittest.TestCase):
    def test_disabled_without_private_credentials(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(configuration())
            self.assertEqual(reconcile_once(), {'enabled': False, 'consulted': 0})

    def test_schedule_only_requests_consultations_and_never_emission(self):
        calls = []
        class Session:
            def post(self, url, **kwargs):
                calls.append((url, kwargs)); return Response()
        with patch.dict(os.environ, {'SRI_SUPABASE_URL':'https://project.supabase.co', 'SRI_SUPABASE_PUBLISHABLE_KEY':'public-fixture', 'SRI_RECONCILE_TOKEN':'a'*64, 'SRI_RECONCILE_INTERVAL':'10'}, clear=True):
            self.assertEqual(configuration()[2], 60)
            result = reconcile_once(Session())
        self.assertEqual(result['consulted'], 1)
        self.assertEqual(calls[0][1]['json'], {'action':'refresh_pending'})
        self.assertEqual(calls[0][1]['allow_redirects'], False)
        self.assertNotIn('a'*64, str(result))
        self.assertEqual(calls[0][1]['headers']['apikey'],'public-fixture')
        self.assertEqual(calls[0][1]['headers']['x-coco-sri-reconcile'],'a'*64)

    def test_credentials_never_follow_a_redirect_or_invalid_endpoint(self):
        for url in ['http://project.supabase.co','https://user:secret@project.supabase.co','https://project.supabase.co/path','https://project.supabase.co?x=1']:
            with patch.dict(os.environ, {'SRI_SUPABASE_URL':url, 'SRI_SUPABASE_PUBLISHABLE_KEY':'public-fixture', 'SRI_RECONCILE_TOKEN':'a'*64}, clear=True):
                self.assertIsNone(configuration())

    def test_old_global_database_key_alone_does_not_enable_the_worker(self):
        with patch.dict(os.environ, {'SRI_SUPABASE_URL':'https://project.supabase.co', 'SRI_SUPABASE_SERVICE_ROLE_KEY':'legacy'}, clear=True):
            self.assertIsNone(configuration())
