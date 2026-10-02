import base64
import copy
import json
import unittest
from xml.etree import ElementTree as ET

import requests
from services.sri.engine import access_key, invoice_xml
from services.sri.openapi import OpenApiSriClient, factura_payload, signed_invoice, validate_key
from test_sri_engine import ISSUE as BASE_ISSUE

ISSUE = {**copy.deepcopy(BASE_ISSUE), 'id': '00000000-0000-4000-8000-000000000001'}
ISSUE['snapshot']['source_number'] = 'FAC-00000001'
ENV = {'SRI_OPENAPI_URL': 'https://sri.example.invalid', 'SRI_OPENAPI_EMAIL': 'coco@example.invalid',
       'SRI_OPENAPI_PASSWORD': 'not-a-real-password', 'SRI_ISSUER_RUC': ISSUE['issuer_ruc'],
       'SRI_OPENAPI_ENVIRONMENT': 'pruebas', 'SRI_OPENAPI_ACCOUNTING': 'SI', 'SRI_OPENAPI_SYNC_CONFIRMED': 'true'}
KEY = access_key(ISSUE)


def xml_fixture(issue=ISSUE):
    xml, key = invoice_xml(issue)
    root = ET.fromstring(xml)
    # A structural fixture, NOT a real cryptographic signature or SRI response.
    ET.SubElement(root, '{http://www.w3.org/2000/09/xmldsig#}Signature')
    return ET.tostring(root, encoding='unicode')


class Response:
    def __init__(self, value, status=200):
        self.value, self.status_code = value, status
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def iter_content(self, size):
        raw = self.value if isinstance(self.value, bytes) else json.dumps(self.value).encode()
        for i in range(0, len(raw), size):
            yield raw[i:i+size]


class Session:
    def __init__(self, responses):
        self.responses, self.calls = list(responses), []
    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if url.endswith('/auth/login'):
            return Response({'accessToken': 'fixture-token'})
        value = self.responses.pop(0)
        if isinstance(value, Exception):
            raise value
        return value if isinstance(value, Response) else Response(value)


def client(responses, env=None):
    session = Session(responses)
    return OpenApiSriClient(session=session, env=ENV if env is None else env), session


def auth_response(**changes):
    return {'success': True, 'claveAcceso': KEY, 'estado': 'AUTORIZADO', 'numeroAutorizacion': KEY,
            'fechaAutorizacion': '2026-09-27T15:00:00-05:00', 'xmlAutorizado': xml_fixture(), **changes}


def row(**changes):
    return {'secuencial': ISSUE['sequential'], 'ambiente': '1', 'rucEmisor': ISSUE['issuer_ruc'],
            'establecimiento': '001', 'puntoEmision': '001', 'identificacionComprador': '1712345678',
            'total': 115, 'claveAcceso': KEY, **changes}


class SriOpenApiTest(unittest.TestCase):
    def test_exact_dto_no_secrets_and_frozen_net_prices(self):
        data = factura_payload(ISSUE, 'SI')
        self.assertEqual(data['secuencial'], '000000001')
        self.assertEqual(data['fechaEmision'], '27/09/2026')
        self.assertEqual(data['emisor']['obligadoContabilidad'], 'SI')
        self.assertEqual(data['comprador']['tipoIdentificacion'], '05')
        self.assertEqual(data['detalles'][0]['impuestos'][0], {'codigo':'2','codigoPorcentaje':'4','tarifa':15,'baseImponible':100,'valor':15})
        self.assertEqual(data['pagos'][0]['total'], 115)
        self.assertNotIn('password', json.dumps(data).lower())
        self.assertNotIn('p12', json.dumps(data).lower())
        self.assertEqual(data['infoAdicional'][0],
                         {'nombre': 'RUC Proveedor', 'valor': ISSUE['snapshot']['provider_ruc']})
        self.assertEqual(data['infoAdicional'][1]['valor'], ISSUE['id'])

    def test_rejects_invalid_amounts_taxes_and_obligation(self):
        for field, value in [('quantity','-1'),('quantity','0'),('unit_price','NaN'),('tax_rate','8')]:
            with self.subTest(field=field,value=value):
                issue=copy.deepcopy(ISSUE);issue['snapshot']['lines'][0][field]=value
                with self.assertRaises(ValueError): factura_payload(issue,'NO')
        with self.assertRaisesRegex(ValueError,'OBLIGATION'): factura_payload(ISSUE,'')
        issue=copy.deepcopy(ISSUE);issue['snapshot']['total']='114'
        with self.assertRaisesRegex(ValueError,'TOTAL_MISMATCH'): factura_payload(issue,'SI')

    def test_key_must_match_environment_source_and_checksum(self):
        self.assertEqual(validate_key(KEY, ISSUE), KEY)
        for key in [KEY[:-1]+'9', access_key({**ISSUE,'environment':'produccion'}),access_key({**ISSUE,'sequential':'000000002'})]:
            with self.assertRaises(ValueError): validate_key(key,ISSUE)
        new=access_key({**ISSUE,'numeric_code':'99999999'})
        self.assertEqual(validate_key(new,ISSUE),new)

    def test_configuration_and_production_fail_closed(self):
        for env in [{**ENV,'SRI_OPENAPI_URL':'http://server'}, {**ENV,'SRI_OPENAPI_URL':'https://user:secret@server'},
                    {**ENV,'SRI_OPENAPI_URL':'https://server?token=secret'}, {**ENV,'SRI_OPENAPI_SYNC_CONFIRMED':'false'}]:
            with self.assertRaises(ValueError): client([],env)
        c,s=client([])
        with self.assertRaisesRegex(ValueError,'ENVIRONMENT_MISMATCH'): c.submit({**ISSUE,'environment':'produccion'})
        c,s=client([],{**ENV,'SRI_OPENAPI_ENVIRONMENT':'produccion'})
        with self.assertRaisesRegex(ValueError,'PRODUCTION_NOT_ENABLED'): c.submit({**ISSUE,'environment':'produccion'})
        self.assertEqual(s.calls,[])

    def test_preflight_is_preview_not_emission(self):
        c,s=client([{'xml':'<factura/>'}]);self.assertTrue(c.preflight(ISSUE)['ready'])
        self.assertTrue(s.calls[-1][1].endswith('/sri/preview/factura'))
        self.assertFalse(any('/emitir/' in x[1] for x in s.calls))

    def test_real_emit_route_and_no_authorization_from_post(self):
        c,s=client([{'estado':'AUTORIZADO','claveAcceso':KEY}])
        self.assertEqual(c.submit(ISSUE)['status'],'processing')
        method,url,kwargs=s.calls[-1]
        self.assertEqual((method,url),('POST',ENV['SRI_OPENAPI_URL']+'/sri/emitir/factura'))
        self.assertFalse(kwargs['allow_redirects'])
        self.assertEqual(kwargs['headers']['Authorization'],'Bearer fixture-token')

    def test_uncertain_emission_has_one_attempt_only(self):
        c,s=client([requests.Timeout('sensitive diagnostic')])
        with self.assertRaisesRegex(ValueError,'^SRI_OPENAPI_TRANSPORT_UNCERTAIN$'): c.submit(ISSUE)
        self.assertEqual(sum('/emitir/' in x[1] for x in s.calls),1)

    def test_redirect_and_body_not_exposed(self):
        c,s=client([Response({'secret':'do not expose'},302)])
        with self.assertRaisesRegex(ValueError,'^SRI_OPENAPI_HTTP_302$'): c.submit(ISSUE)
        c,s=client([b'{invalid'])
        with self.assertRaisesRegex(ValueError,'INVALID_RESPONSE'): c.submit(ISSUE)

    def test_async_never_marked_authorized_or_retried(self):
        c,s=client([{'estado':'EN_COLA','jobId':'somejob'}])
        result=c.submit(ISSUE)
        self.assertTrue(result['review_required']);self.assertNotIn('access_key',result)
        self.assertEqual(len(s.calls),2)

    def test_timeout_recovery_uses_lookup_not_post(self):
        c,s=client([{'data':[row()], 'meta':{'totalPages':1}}, {'success':False,'claveAcceso':KEY,'estado':'NO ENCONTRADO'}])
        result=c.refresh(ISSUE)
        self.assertEqual(result['access_key'],KEY)
        self.assertEqual(result['status'],'processing')
        self.assertFalse(any('/emitir/' in x[1] for x in s.calls))
        self.assertTrue(s.calls[-1][1].endswith('/sri/autorizar/'+KEY))

    def test_absence_is_not_permission_to_reissue(self):
        c,s=client([{'data':[], 'meta':{'totalPages':0}}])
        self.assertTrue(c.refresh(ISSUE)['review_required'])
        self.assertFalse(any('/emitir/' in x[1] for x in s.calls))

    def test_lookup_exact_sequence_and_multiple_matches_rejected(self):
        c,s=client([{'data':[row(secuencial='000000002'),row()], 'meta':{'totalPages':1}}])
        self.assertEqual(c.lookup(ISSUE),KEY)
        c,s=client([{'data':[row(),row()], 'meta':{'totalPages':1}}])
        with self.assertRaisesRegex(ValueError,'COLLISION'):c.lookup(ISSUE)
        c,s=client([{'data':[row(total=999)], 'meta':{'totalPages':1}}])
        with self.assertRaisesRegex(ValueError,'COLLISION'):c.lookup(ISSUE)

    def test_paginated_reconciliation(self):
        c,s=client([{'data':[],'meta':{'totalPages':2}}, {'data':[row()],'meta':{'totalPages':2}}])
        self.assertEqual(c.lookup(ISSUE),KEY)
        self.assertEqual(s.calls[-1][2]['params']['page'],2)

    def test_authorization_archives_validated_xml_and_ride(self):
        c,s=client([auth_response(),{'claveAcceso':KEY,'estado':'AUTORIZADO'},b'%PDF-1.7\nfixture'])
        result=c.refresh({**ISSUE,'access_key':KEY})
        self.assertEqual(result['status'],'authorized')
        root=ET.fromstring(base64.b64decode(result['authorized_xml']))
        self.assertEqual(root.findtext('numeroAutorizacion'),KEY)
        self.assertEqual(ET.fromstring(root.findtext('comprobante')).tag,'factura')
        self.assertTrue(base64.b64decode(result['ride_pdf']).startswith(b'%PDF-'))

    def test_no_provisional_ride_and_no_unknown_authorization(self):
        c,s=client([auth_response(),{'claveAcceso':KEY,'estado':'PENDIENTE'}])
        result=c.refresh({**ISSUE,'access_key':KEY})
        self.assertEqual(result['status'],'processing');self.assertNotIn('ride_pdf',result)
        for changes in [{'numeroAutorizacion':'wrong'}, {'success':False}, {'fechaAutorizacion':'2026-09-27T15:00:00'}]:
            c,s=client([auth_response(**changes)])
            with self.assertRaises(ValueError): c.refresh({**ISSUE,'access_key':KEY})

    def test_xml_rejects_entities_unsigned_and_wrong_totals(self):
        for xml in ['<!DOCTYPE factura [<!ENTITY x "attack">]>'+xml_fixture(), invoice_xml(ISSUE)[0].decode(),
                    xml_fixture().replace('<importeTotal>115.00','<importeTotal>999.00'),
                    xml_fixture().replace('<cantidad>1','<cantidad>2'),
                    xml_fixture().replace('<ruc>1790012345001','<ruc>1790012345999')]:
            with self.subTest(xml=xml[:50]):
                with self.assertRaises(ValueError): signed_invoice(xml,ISSUE,KEY)

    def test_bad_pdf_and_oversized_response(self):
        c,s=client([auth_response(),{'claveAcceso':KEY,'estado':'AUTORIZADO'},b'<html>server error</html>'])
        with self.assertRaisesRegex(ValueError,'INVALID_RIDE'): c.refresh({**ISSUE,'access_key':KEY})
        c,s=client([b'X'*(1024*1024+1)])
        with self.assertRaisesRegex(ValueError,'RESPONSE_TOO_LARGE'): c.submit(ISSUE)


if __name__=='__main__': unittest.main()
