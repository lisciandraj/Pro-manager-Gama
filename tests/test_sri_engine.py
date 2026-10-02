import copy
import unittest
from xml.etree import ElementTree as ET

from services.sri.engine import access_key, invoice_xml


ISSUE = {
    'environment': 'pruebas', 'issuer_ruc': '1790012345001',
    'establishment': '001', 'emission_point': '001',
    'sequential': '000000001', 'numeric_code': '12345678',
    'snapshot': {
        'issue_date': '2026-09-27', 'issuer': 'Empresa de prueba',
        'address': 'Quito', 'customer': 'Cliente',
        'identification': '1712345678', 'customer_address': 'Quito',
        'customer_email': 'cliente@example.invalid',
        'provider_ruc': '1790012345001', 'payment_code': '01',
        'subtotal': '100.00', 'tax': '15.00', 'total': '115.00',
        'lines': [{'code': 'A', 'description': 'Producto', 'quantity': '1',
                   'unit_price': '100', 'tax_rate': '15', 'subtotal': '100'}]
    }
}


class SriEngineTest(unittest.TestCase):
    def test_key_and_invoice_amounts(self):
        xml, key = invoice_xml(ISSUE)
        self.assertEqual(key, '2709202601179001234500110010010000000011234567813')
        self.assertEqual(len(key), 49)
        root = ET.fromstring(xml)
        self.assertEqual(root.findtext('infoFactura/importeTotal'), '115.00')
        self.assertEqual(root.findtext('infoTributaria/claveAcceso'), key)
        self.assertEqual(root.find('infoAdicional/campoAdicional').attrib['nombre'],
                         'RUC Proveedor')

    def test_bad_tax_and_amount_cannot_be_submitted(self):
        changed = copy.deepcopy(ISSUE)
        changed['snapshot']['lines'][0]['tax_rate'] = '8'
        with self.assertRaisesRegex(ValueError, 'SRI_UNSUPPORTED_TAX_RATE'):
            invoice_xml(changed)
        changed['snapshot']['lines'][0]['tax_rate'] = '15'
        changed['snapshot']['total'] = '114'
        with self.assertRaisesRegex(ValueError, 'SRI_TOTAL_MISMATCH'):
            invoice_xml(changed)

    def test_key_changes_by_sequence_and_environment(self):
        changed = copy.deepcopy(ISSUE)
        changed['sequential'] = '000000002'
        self.assertNotEqual(access_key(changed), access_key(ISSUE))
        changed['environment'] = 'produccion'
        self.assertNotEqual(access_key(changed), access_key(ISSUE))


if __name__ == '__main__':
    unittest.main()
