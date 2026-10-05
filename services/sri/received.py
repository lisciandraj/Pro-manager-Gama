"""Bind a received retention to an actual SRI authorization and ERP invoice."""
import re
from datetime import date
from decimal import Decimal
from pathlib import Path
from functools import lru_cache
from lxml import etree
from .engine import authorize_sri
from .documents import amount


def parse(xml):
    raw = xml.encode() if isinstance(xml, str) else xml
    if len(raw) > 1048576 or re.search(br'<!\s*(DOCTYPE|ENTITY)', raw, re.I):
        raise ValueError('SRI_UNSAFE_XML')
    try:
        return etree.fromstring(raw, etree.XMLParser(resolve_entities=False, no_network=True, load_dtd=False))
    except etree.XMLSyntaxError as exc:
        raise ValueError('SRI_XML_INVALID') from exc


def single(root, path):
    nodes = root.findall(path)
    if len(nodes) != 1 or nodes[0].text is None:
        raise ValueError('SRI_RECEIVED_FIELDS_INVALID')
    return nodes[0].text.strip()


def key_valid(key):
    if not re.fullmatch('[0-9]{49}', key): return False
    check = 11 - sum(int(v) * (i % 6 + 2) for i, v in enumerate(reversed(key[:48]))) % 11
    return key[-1] == str(0 if check == 11 else 1 if check == 10 else check)


@lru_cache(maxsize=2)
def schema(version):
    if version not in ('1.0.0','2.0.0'): raise ValueError('SRI_RETENTION_VERSION_UNSUPPORTED')
    # Only these bundled, trusted schema files can resolve internal entities.
    parser = etree.XMLParser(no_network=True, load_dtd=False, resolve_entities=True)
    return etree.XMLSchema(etree.parse(str(Path(__file__).parent/'schemas'/('ComprobanteRetencion_V'+version+'.xsd')), parser))


def content(xml):
    root = parse(xml)
    if root.tag == 'autorizacion':
        if single(root,'estado') != 'AUTORIZADO': raise ValueError('SRI_NOT_AUTHORIZED')
        document = parse(single(root,'comprobante'))
        if single(root,'numeroAutorizacion') != single(document,'infoTributaria/claveAcceso'):
            raise ValueError('SRI_ACCESS_KEY_MISMATCH')
        return document
    return root


def verify(xml, invoice, lookup=authorize_sri):
    uploaded = content(xml)
    key = single(uploaded,'infoTributaria/claveAcceso')
    if uploaded.tag != 'comprobanteRetencion' or not key_valid(key) or key[8:10] != '07' or key[23] not in '12':
        raise ValueError('SRI_RECEIVED_DOCUMENT_INVALID')
    result = lookup(key, 'pruebas' if key[23] == '1' else 'produccion')
    if result.get('status') != 'authorized' or result.get('authorization') != key or not result.get('authorized_at'):
        raise ValueError('SRI_NOT_AUTHORIZED')
    root = content(result['authorized_xml'])
    if single(root,'infoTributaria/claveAcceso') != key or single(root,'infoTributaria/codDoc') != '07':
        raise ValueError('SRI_ACCESS_KEY_MISMATCH')
    if len(root.findall('{http://www.w3.org/2000/09/xmldsig#}Signature')) != 1:
        raise ValueError('SRI_RECEIVED_SIGNATURE_MISSING')
    try: schema(root.get('version')).assertValid(root)
    except etree.DocumentInvalid as exc: raise ValueError('SRI_DOCUMENT_SCHEMA_INVALID') from exc
    issuer = single(root,'infoTributaria/ruc')
    if issuer != invoice['customer_identification'] or issuer != key[10:23] or single(root,'infoCompRetencion/identificacionSujetoRetenido') != invoice['issuer_ruc']:
        raise ValueError('SRI_RECEIVED_PARTY_MISMATCH')
    fiscal = invoice['fiscal_number'].replace('-','')
    if not re.fullmatch('[0-9]{15}', fiscal): raise ValueError('SRI_INVOICE_FISCAL_NUMBER_REQUIRED')
    issue_date = single(root,'infoCompRetencion/fechaEmision')
    try: issued = date.fromisoformat('-'.join(reversed(issue_date.split('/'))))
    except ValueError as exc: raise ValueError('SRI_INVALID_DATE') from exc
    if issue_date.replace('/','') != key[:8]: raise ValueError('SRI_ACCESS_KEY_MISMATCH')
    source_date = date.fromisoformat(invoice['issue_date'])
    if issued < source_date: raise ValueError('SRI_INVALID_DATE')
    version = root.get('version')
    taxes = []
    if version == '2.0.0':
        docs = [d for d in root.findall('docsSustento/docSustento') if single(d,'numDocSustento') == fiscal]
        if len(docs) != 1 or single(docs[0],'codDocSustento') != '01': raise ValueError('SRI_RECEIVED_INVOICE_MISMATCH')
        taxes = docs[0].findall('retenciones/retencion')
    else:
        taxes = [d for d in root.findall('impuestos/impuesto') if single(d,'numDocSustento') == fiscal and single(d,'codDocSustento') == '01']
    lines=[];bases={'income':Decimal('0'),'vat':Decimal('0')};total=Decimal('0')
    for tax in taxes:
        kind={'1':'income','2':'vat'}.get(single(tax,'codigo'))
        if not kind: raise ValueError('SRI_RECEIVED_TAX_UNSUPPORTED')
        rate=amount(single(tax,'porcentajeRetener'));base=amount(single(tax,'baseImponible'));value=amount(single(tax,'valorRetenido'))
        if rate>100 or (base*rate/100).quantize(Decimal('.01'),rounding='ROUND_HALF_UP') != value:
            raise ValueError('SRI_WITHHOLDING_TOTAL_MISMATCH')
        if value == 0: continue
        if base<=0 or rate<=0: raise ValueError('SRI_WITHHOLDING_TOTAL_MISMATCH')
        code=single(tax,'codigoRetencion')
        if not re.fullmatch('[0-9]{1,5}',code): raise ValueError('SRI_RECEIVED_TAX_UNSUPPORTED')
        bases[kind]+=base;total+=value
        lines.append({'tax_kind':kind,'code':code,'base':str(base),'rate':str(rate),'amount':str(value)})
    if not lines or total<=0 or bases['income']>amount(invoice['subtotal']) or bases['vat']>amount(invoice['tax']):
        raise ValueError('SRI_RECEIVED_INVOICE_MISMATCH')
    number='-'.join(single(root,'infoTributaria/'+field) for field in ['estab','ptoEmi','secuencial'])
    return {'access_key':key,'issuer_ruc':issuer,'number':number,'issued_on':issued.isoformat(),'amount':str(total),'lines':lines,'authorized_at':result['authorized_at'],'authorized_xml':etree.tostring(root,encoding='unicode')}


def inspect(xml, own_ruc):
    root=content(xml)
    key=single(root,'infoTributaria/claveAcceso')
    if root.tag!='comprobanteRetencion' or not key_valid(key) or key[8:10]!='07' or single(root,'infoCompRetencion/identificacionSujetoRetenido')!=own_ruc:
        raise ValueError('SRI_RECEIVED_PARTY_MISMATCH')
    issuer=single(root,'infoTributaria/ruc')
    if issuer!=key[10:23]: raise ValueError('SRI_ACCESS_KEY_MISMATCH')
    paths='docsSustento/docSustento' if root.get('version')=='2.0.0' else 'impuestos/impuesto'
    sources=sorted({single(d,'numDocSustento') for d in root.findall(paths) if single(d,'codDocSustento')=='01'})
    if not sources or len(sources)>50: raise ValueError('SRI_RECEIVED_FIELDS_INVALID')
    if any(single(d,'codDocSustento')!='01' for d in root.findall(paths)):
        raise ValueError('SRI_RECEIVED_TAX_UNSUPPORTED')
    return {'access_key':key,'issuer_ruc':issuer,'sources':sources}


def verify_batch(xml, invoices, lookup=authorize_sri):
    if not isinstance(invoices,list) or not 1<=len(invoices)<=50:
        raise ValueError('SRI_RECEIVED_FIELDS_INVALID')
    key=single(content(xml),'infoTributaria/claveAcceso')
    if not key_valid(key) or key[8:10]!='07' or key[23] not in '12': raise ValueError('SRI_RECEIVED_DOCUMENT_INVALID')
    result=lookup(key,'pruebas' if key[23]=='1' else 'produccion')
    if result.get('status')!='authorized' or result.get('authorization')!=key: raise ValueError('SRI_NOT_AUTHORIZED')
    sources=inspect(result['authorized_xml'],invoices[0]['issuer_ruc'])['sources']
    if sources!=sorted(i['fiscal_number'].replace('-','') for i in invoices): raise ValueError('SRI_RECEIVED_INVOICE_MISMATCH')
    return {'rows':[{'invoice_id':i['id'],**verify(xml,i,lookup=lambda *_:result)} for i in invoices]}


def inspect_authorized(xml, own_ruc, lookup=authorize_sri):
    root=content(xml);key=single(root,'infoTributaria/claveAcceso')
    if not key_valid(key) or key[8:10]!='07' or key[23] not in '12':
        raise ValueError('SRI_RECEIVED_DOCUMENT_INVALID')
    result=lookup(key,'pruebas' if key[23]=='1' else 'produccion')
    if result.get('status')!='authorized' or result.get('authorization')!=key or not result.get('authorized_at'):
        raise ValueError('SRI_NOT_AUTHORIZED')
    actual=content(result['authorized_xml'])
    if single(actual,'infoTributaria/claveAcceso')!=key:
        raise ValueError('SRI_ACCESS_KEY_MISMATCH')
    return inspect(result['authorized_xml'],own_ruc)
