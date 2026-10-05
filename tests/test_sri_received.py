import copy
import unittest
from xml.etree import ElementTree as ET
from services.sri.engine import document_xml, access_key, element
from services.sri.received import verify, inspect_authorized, verify_batch
from test_sri_documents import fixture

SIG='''<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:SignedInfo><ds:CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/><ds:SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1"/><ds:Reference URI="#comprobante"><ds:DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1"/><ds:DigestValue>AA==</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:SignatureValue>AA==</ds:SignatureValue></ds:Signature>'''


def received(version='2.0.0'):
    issue=fixture('07');issue['issuer_ruc']='1719304188001';issue['snapshot']['identification']='1790012345001'
    xml,key=document_xml(issue);root=ET.fromstring(xml)
    if version=='1.0.0':
        root.set('version',version)
        party=root.find('infoCompRetencion/parteRel')
        if party is not None:root.find('infoCompRetencion').remove(party)
        docs=root.find('docsSustento');root.remove(docs);taxes=ET.Element('impuestos');root.insert(2,taxes)
        for tax in docs.findall('docSustento/retenciones/retencion'):
            item=ET.SubElement(taxes,'impuesto')
            for tag in ['codigo','codigoRetencion','baseImponible','porcentajeRetener','valorRetenido']:element(item,tag,tax.findtext(tag))
            for tag,value in [('codDocSustento','01'),('numDocSustento','001001000000007'),('fechaEmisionDocSustento','25/09/2026')]:element(item,tag,value)
    root.append(ET.fromstring(SIG));xml=ET.tostring(root,encoding='unicode')
    invoice={'id':'fixture','issuer_ruc':'1790012345001','customer_identification':'1719304188001','fiscal_number':'001-001-000000007','issue_date':'2026-09-25','subtotal':100,'tax':15}
    response={'status':'authorized','authorization':key,'authorized_at':'2026-09-27T12:00:00-05:00','authorized_xml':xml}
    return xml,invoice,response

class SriReceivedTest(unittest.TestCase):
    def test_both_retention_versions_use_the_actual_online_authorization(self):
        for version in ['1.0.0','2.0.0']:
            xml,invoice,response=received(version);calls=[]
            def lookup(key,environment):calls.append((key,environment));return response
            r=verify(xml,invoice,lookup)
            self.assertEqual(r['amount'],'13.00');self.assertEqual([l['tax_kind'] for l in r['lines']],['income','vat']);self.assertEqual(len(calls),1);self.assertEqual(calls[0][1],'pruebas')
            self.assertEqual(inspect_authorized(xml,invoice['issuer_ruc'],lookup)['sources'],['001001000000007'])
            self.assertEqual(verify_batch(xml,[invoice],lookup)['rows'][0]['invoice_id'],'fixture')

    def test_local_authorized_envelope_cannot_fabricate_sri_authorization(self):
        xml,invoice,response=received()
        root=ET.Element('autorizacion');element(root,'estado','AUTORIZADO');element(root,'numeroAutorizacion',response['authorization']);element(root,'comprobante',xml)
        envelope=ET.tostring(root)
        with self.assertRaisesRegex(ValueError,'NOT_AUTHORIZED'):verify(envelope,invoice,lambda *_:{'status':'processing'})
        with self.assertRaisesRegex(ValueError,'NOT_AUTHORIZED'):verify(xml,invoice,lambda *_:{**response,'authorization':'9'*49})

    def test_customer_company_invoice_and_tax_bases_are_bound(self):
        xml,invoice,response=received()
        for patch,error in [({'issuer_ruc':'1999999999001'},'PARTY_MISMATCH'),({'customer_identification':'1999999999001'},'PARTY_MISMATCH'),({'fiscal_number':'001-001-000000099'},'INVOICE_MISMATCH'),({'subtotal':99},'INVOICE_MISMATCH'),({'tax':14},'INVOICE_MISMATCH')]:
            with self.subTest(patch=patch),self.assertRaisesRegex(ValueError,error):verify(xml,{**invoice,**patch},lambda *_:response)
        with self.assertRaisesRegex(ValueError,'INVOICE_MISMATCH'):verify_batch(xml,[{**invoice,'fiscal_number':'001-001-000000099'}],lambda *_:response)

    def test_tampered_uploaded_amounts_are_never_used(self):
        xml,invoice,response=received();root=ET.fromstring(xml);root.find('.//valorRetenido').text='99.00'
        r=verify(ET.tostring(root),invoice,lambda *_:response);self.assertEqual(r['amount'],'13.00')

    def test_dtd_invalid_keys_and_unsigned_online_documents_are_rejected(self):
        xml,invoice,response=received()
        with self.assertRaisesRegex(ValueError,'UNSAFE_XML'):verify(b'<!DOCTYPE x [<!ENTITY t SYSTEM "file:///etc/passwd">]>'+xml.encode(),invoice,lambda *_:response)
        bad=xml.replace(response['authorization'],'9'*49)
        with self.assertRaisesRegex(ValueError,'DOCUMENT_INVALID'):verify(bad,invoice,lambda *_:response)
        root=ET.fromstring(xml);root.remove(root.find('{http://www.w3.org/2000/09/xmldsig#}Signature'))
        with self.assertRaisesRegex(ValueError,'SIGNATURE_MISSING'):verify(xml,invoice,lambda *_:{**response,'authorized_xml':ET.tostring(root,encoding='unicode')})
