import copy
import unittest
from xml.etree import ElementTree as ET

from services.sri.engine import access_key, document_xml
from services.sri.documents import validate_xml, signed_document, document_ride
from services.sri.openapi_documents import payload
from test_sri_openapi import client
from test_sri_engine import ISSUE


def fixture(code):
    issue = {**copy.deepcopy(ISSUE), 'document_type': code, 'id': '00000000-0000-4000-8000-000000000017'}
    s = issue['snapshot']
    s.update(source_number='DOC-00000017', accounting_obligation='SI', support_number='001-001-000000007',
             support_date='2026-09-25', support_authorization='2509202601179001234500110010010000000071234567814',
             support_code='01', reason='Devolucion de mercaderia', withheld_total='13.00',
             withholdings=[{'tax_kind': 'IR', 'code': '312', 'base': '100', 'rate': '2.5', 'amount': '2.50'},
                           {'tax_kind': 'IVA', 'code': '2', 'base': '15', 'rate': '70', 'amount': '10.50'}],
             transport_start='2026-09-27', transport_end='2026-09-28', departure_address='Quito',
             carrier_name='Transportista de prueba', carrier_identification='1712345678', plate='PBA1234',
             recipients=[{'identification': '1712345678', 'customer': 'Cliente', 'address': 'Quito',
                          'reason': 'Venta de mercaderia', 'lines': [{'code': 'A', 'description': 'Producto', 'quantity': '2'}]}])
    return issue


class SriDocumentsTest(unittest.TestCase):
    def test_upstream_routes_are_exact_and_preflight_cannot_emit(self):
        for code, route in [('04', 'nota-credito'), ('06', 'guia-remision'), ('07', 'retencion')]:
            with self.subTest(code=code):
                issue = fixture(code)
                issue['id'] = '00000000-0000-4000-8000-000000000017'
                issue['snapshot']['carrier_identification'] = '1790012345001'
                key = access_key(issue)
                c, session = client([{'claveAcceso': key, 'estado': 'RECIBIDA'}])
                self.assertTrue(c.preflight(issue)['ready'])
                self.assertEqual(session.calls, [])
                c.submit(issue)
                calls = [call for call in session.calls if '/emitir/' in call[1]]
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][1].split('/emitir/')[1], route)
                self.assertEqual(calls[0][2]['json']['secuencial'], issue['sequential'])

    def test_upstream_cannot_silently_drop_unsupported_supplier_or_carrier_fields(self):
        for code, patch, error in [('03', {}, 'DOCUMENT_UNSUPPORTED'),
                                  ('06', {'carrier_identification': '1712345678'}, 'CARRIER_RUC_REQUIRED'),
                                  ('07', {'related_party': True}, 'SPECIAL_REGIME_UNSUPPORTED')]:
            issue = fixture(code)
            issue['snapshot'].update(patch)
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, error):
                payload(issue, 'SI')

    def test_signed_authorization_must_match_the_frozen_operation(self):
        # Structural signature fixture only: SRI verifies cryptography itself.
        signature = '''<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:SignedInfo>
        <ds:CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
        <ds:SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1"/>
        <ds:Reference URI="#comprobante"><ds:DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1"/>
        <ds:DigestValue>AA==</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:SignatureValue>AA==</ds:SignatureValue></ds:Signature>'''
        for code in ('03', '04', '06', '07'):
            issue = fixture(code)
            xml, key = document_xml(issue)
            root = ET.fromstring(xml)
            root.append(ET.fromstring(signature))
            signed = ET.tostring(root, encoding='unicode')
            with self.subTest(code=code):
                signed_document(signed, issue, key)
                root.find('infoTributaria/secuencial').text = '000000002'
                with self.assertRaisesRegex(ValueError, 'DOCUMENT_MISMATCH'):
                    signed_document(ET.tostring(root, encoding='unicode'), issue, key)
                root = ET.fromstring(signed)
                leaf = root.find('.//cantidad') if code != '07' else root.find('.//valorRetenido')
                leaf.text = '99'
                with self.assertRaisesRegex(ValueError, 'DOCUMENT_MISMATCH'):
                    signed_document(ET.tostring(root, encoding='unicode'), issue, key)

    def test_ride_requires_authorization_and_keeps_every_long_route_stop(self):
        import io
        from pypdf import PdfReader
        issue = fixture('06')
        with self.assertRaisesRegex(ValueError, 'NOT_AUTHORIZED'):
            document_ride(issue)
        issue['authorization'] = access_key(issue)
        issue['snapshot']['recipients'] = [{**copy.deepcopy(issue['snapshot']['recipients'][0]),
            'customer': f'Cliente numero {i}', 'address': 'Direccion de entrega ' * 10} for i in range(18)]
        data = document_ride(issue)
        reader = PdfReader(io.BytesIO(data))
        self.assertGreater(len(reader.pages), 1)
        text = '\n'.join(page.extract_text() for page in reader.pages)
        for i in range(18):
            self.assertIn(f'Cliente numero {i}', text)
        self.assertIn('DOC-00000017', text)
    def test_official_schemas_and_access_key_bind_document_type(self):
        for code, root_name in [('03', 'liquidacionCompra'), ('04', 'notaCredito'),
                                ('06', 'guiaRemision'), ('07', 'comprobanteRetencion')]:
            with self.subTest(code=code):
                issue = fixture(code)
                xml, key = document_xml(issue)
                root = ET.fromstring(xml)
                self.assertEqual(root.tag, root_name)
                self.assertEqual(key[8:10], code)
                self.assertEqual(root.findtext('infoTributaria/codDoc'), code)
                self.assertEqual(root.findtext('infoTributaria/claveAcceso'), key)
                self.assertEqual(key, access_key(issue))
                validate_xml(xml, code)

    def test_credit_note_support_and_amounts_cannot_change(self):
        issue = fixture('04')
        xml, _ = document_xml(issue)
        root = ET.fromstring(xml)
        self.assertEqual(root.findtext('infoNotaCredito/numDocModificado'), '001-001-000000007')
        self.assertEqual(root.findtext('infoNotaCredito/valorModificacion'), '115.00')
        for field, value, error in [('support_number', 'FAC-00000007', 'SUPPORT_DOCUMENT'),
                                     ('support_date', '2026-09-28', 'DATE_INVALID'),
                                     ('reason', '', 'REASON_REQUIRED'), ('total', '114', 'TOTAL_MISMATCH')]:
            invalid = copy.deepcopy(issue)
            invalid['snapshot'][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, error):
                document_xml(invalid)

    def test_liquidation_excludes_supplier_with_ruc(self):
        issue = fixture('03')
        issue['snapshot']['identification'] = '1790012345001'
        with self.assertRaisesRegex(ValueError, 'REQUIRES_NO_RUC'):
            document_xml(issue)

    def test_guide_retains_each_stop_and_goods_without_inventing_invoice(self):
        issue = fixture('06')
        issue['snapshot']['recipients'].append({'identification': '1790012345001', 'customer': 'Agencia',
             'address': 'Guayaquil', 'reason': 'Venta de mercaderia', 'lines': [{'code': 'B', 'description': 'Otro articulo', 'quantity': '3.5'}]})
        root = ET.fromstring(document_xml(issue)[0])
        recipients = root.findall('destinatarios/destinatario')
        self.assertEqual(len(recipients), 2)
        self.assertEqual(recipients[1].findtext('detalles/detalle/cantidad'), '3.5')
        self.assertIsNone(recipients[0].find('numDocSustento'))
        issue['snapshot']['transport_end'] = '2026-09-26'
        with self.assertRaisesRegex(ValueError, 'TRANSPORT_DATES_INVALID'):
            document_xml(issue)

    def test_withholding_uses_iva_amount_as_base_and_exact_selected_rates(self):
        issue = fixture('07')
        root = ET.fromstring(document_xml(issue)[0])
        self.assertEqual(root.findtext('infoCompRetencion/periodoFiscal'), '09/2026')
        rows = root.findall('docsSustento/docSustento/retenciones/retencion')
        self.assertEqual(rows[1].findtext('baseImponible'), '15.00')
        self.assertEqual(rows[1].findtext('valorRetenido'), '10.50')
        for field, value, error in [('base', '100', 'BASE_INVALID'), ('amount', '1', 'AMOUNT_INVALID'),
                                     ('rate', '101', 'AMOUNT_INVALID'), ('code', '', 'CODE_REQUIRED')]:
            invalid = copy.deepcopy(issue)
            invalid['snapshot']['withholdings'][1][field] = value
            if field == 'base':
                invalid['snapshot']['withholdings'][1]['amount'] = '70'
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, error):
                document_xml(invalid)

    def test_negative_nonfinite_zero_and_special_regimes_rejected(self):
        for code in ('03', '04', '07'):
            for field, value in [('quantity', '0'), ('quantity', '-1'), ('unit_price', 'NaN'), ('tax_rate', '8')]:
                invalid = fixture(code)
                invalid['snapshot']['lines'][0][field] = value
                with self.subTest(code=code, field=field), self.assertRaises(ValueError):
                    document_xml(invalid)
        issue = fixture('07')
        issue['snapshot']['foreign_purchase'] = True
        with self.assertRaisesRegex(ValueError, 'SPECIAL_REGIME_UNSUPPORTED'):
            document_xml(issue)

    def test_official_schema_rejects_missing_required_field_and_unsafe_xml(self):
        for code in ('03', '04', '06', '07'):
            xml, _ = document_xml(fixture(code))
            root = ET.fromstring(xml)
            root.find('infoTributaria').remove(root.find('infoTributaria/ruc'))
            with self.assertRaisesRegex(ValueError, 'SCHEMA_INVALID'):
                validate_xml(ET.tostring(root), code)
            with self.assertRaisesRegex(ValueError, 'UNSAFE_XML'):
                validate_xml(b'<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]>' + xml, code)


if __name__ == '__main__':
    unittest.main()
