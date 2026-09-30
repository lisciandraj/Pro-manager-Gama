"""Coco adapter for Open API Facturación SRI, pinned contract b41a7c79.

No emission retry: upstream does not expose a durable idempotency key. A lost
response must be reconciled by the reserved fiscal series, never re-issued.
Only ordinary domestic invoices are mapped; credentials stay on this server.
"""
import base64
import json
import os
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET

import requests
from .engine import TAX_CODES, access_key, cents, invoice_xml

MAX_BYTES = 1024 * 1024
ENVIRONMENTS = {'pruebas': '1', 'produccion': '2'}
REJECTED = {'DEVUELTA', 'NO AUTORIZADO', 'RECHAZADO'}


def number(value, positive=False):
    try:
        result = Decimal(str(value))
        if not result.is_finite() or result < 0 or (positive and result == 0):
            raise ValueError('SRI_INVALID_AMOUNT')
        return result
    except (InvalidOperation, TypeError) as exc:
        raise ValueError('SRI_INVALID_AMOUNT') from exc


def validate_key(key, issue):
    if not isinstance(key, str) or not re.fullmatch(r'[0-9]{49}', key):
        raise ValueError('SRI_INVALID_ACCESS_KEY')
    # The upstream engine owns the eight random digits, not the fiscal series.
    if key != access_key({**issue, 'numeric_code': key[39:47]}):
        raise ValueError('SRI_ACCESS_KEY_MISMATCH')
    return key


def factura_payload(issue, accounting):
    if accounting not in ('SI', 'NO'):
        raise ValueError('SRI_ACCOUNTING_OBLIGATION_REQUIRED')
    s = issue['snapshot']
    if issue['environment'] not in ENVIRONMENTS:
        raise ValueError('SRI_ENVIRONMENT_INVALID')
    for key in ('issuer', 'address', 'customer', 'customer_address', 'provider_ruc'):
        if not str(s.get(key, '')).strip():
            raise ValueError('SRI_INCOMPLETE_SNAPSHOT')
    if not re.fullmatch(r'[0-9]{13}', s['provider_ruc']):
        raise ValueError('SRI_PROVIDER_RUC_REQUIRED')
    if not re.fullmatch(r'[0-9]{10}|[0-9]{13}', s['identification']):
        raise ValueError('SRI_UNSUPPORTED_CUSTOMER_ID')
    # Reuse the existing strict total / VAT / payment-code verification.
    for line in s['lines']:
        number(line['quantity'], positive=True)
        number(line['unit_price'])
        number(line['tax_rate'])
    for key in ('subtotal', 'tax', 'total'):
        number(s[key])
    invoice_xml(issue)
    details = []
    for line in s['lines']:
        quantity, price, rate = map(number, (line['quantity'], line['unit_price'], line['tax_rate']))
        base = cents(quantity * price)
        details.append({
            'codigoPrincipal': str(line['code'] or 'SIN-CODIGO'),
            'descripcion': str(line['description']), 'cantidad': float(quantity),
            'precioUnitario': float(price), 'descuento': 0,
            'impuestos': [{'codigo': '2', 'codigoPorcentaje': TAX_CODES[rate],
                          'tarifa': float(rate), 'baseImponible': float(base),
                          'valor': float(cents(base * rate / 100))}],
        })
    buyer = {'tipoIdentificacion': '04' if len(s['identification']) == 13 else '05',
             'identificacion': s['identification'], 'razonSocial': s['customer'],
             'direccion': s['customer_address']}
    if s.get('customer_email'):
        buyer['email'] = s['customer_email']
    return {
        'ambiente': ENVIRONMENTS[issue['environment']], 'tipoEmision': '1',
        'fechaEmision': date.fromisoformat(s['issue_date']).strftime('%d/%m/%Y'),
        'secuencial': issue['sequential'],
        'emisor': {'ruc': issue['issuer_ruc'], 'razonSocial': s['issuer'],
                   'dirMatriz': s['address'], 'dirEstablecimiento': s['address'],
                   'establecimiento': issue['establishment'], 'puntoEmision': issue['emission_point'],
                   'obligadoContabilidad': accounting},
        'comprador': buyer, 'detalles': details,
        'pagos': [{'formaPago': s['payment_code'], 'total': float(cents(s['total']))}],
        'infoAdicional': [
            {'nombre': 'RUC PROVEEDOR SISTEMA DE FACTURACION', 'valor': s['provider_ruc']},
            {'nombre': 'COCO_ID', 'valor': issue['id']},
            {'nombre': 'COCO_FACTURA', 'valor': s['source_number']},
        ],
    }


def signed_invoice(xml, issue, key):
    """Bind the SRI-returned signed invoice to Coco's immutable snapshot.

    The SRI verifies XAdES; this check does not claim independent cryptographic
    signature validation. Reject entities, duplicate fields and altered lines.
    """
    if not isinstance(xml, str) or len(xml.encode('utf-8')) > MAX_BYTES:
        raise ValueError('SRI_INVALID_AUTHORIZED_XML')
    if re.search(r'<!\s*(DOCTYPE|ENTITY)', xml, re.I):
        raise ValueError('SRI_UNSAFE_XML')
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as exc:
        raise ValueError('SRI_INVALID_AUTHORIZED_XML') from exc
    if root.tag != 'factura' or root.get('id') != 'comprobante':
        raise ValueError('SRI_INVALID_AUTHORIZED_XML')
    if len(root.findall('{http://www.w3.org/2000/09/xmldsig#}Signature')) != 1:
        raise ValueError('SRI_UNSIGNED_AUTHORIZATION')
    def text(path):
        nodes = root.findall(path)
        if len(nodes) != 1 or nodes[0].text is None:
            raise ValueError('SRI_INVALID_AUTHORIZED_XML')
        return nodes[0].text.strip()
    s = issue['snapshot']
    expected = {
        'infoTributaria/claveAcceso': key, 'infoTributaria/ruc': issue['issuer_ruc'],
        'infoTributaria/ambiente': ENVIRONMENTS[issue['environment']],
        'infoTributaria/codDoc': '01', 'infoTributaria/estab': issue['establishment'],
        'infoTributaria/ptoEmi': issue['emission_point'], 'infoTributaria/secuencial': issue['sequential'],
        'infoFactura/identificacionComprador': s['identification'],
        'infoFactura/fechaEmision': date.fromisoformat(s['issue_date']).strftime('%d/%m/%Y'),
    }
    if any(text(path) != value for path, value in expected.items()):
        raise ValueError('SRI_AUTHORIZATION_DOCUMENT_MISMATCH')
    if cents(text('infoFactura/totalSinImpuestos')) != cents(s['subtotal']) or cents(text('infoFactura/importeTotal')) != cents(s['total']):
        raise ValueError('SRI_TOTAL_MISMATCH')
    lines = root.findall('detalles/detalle')
    if len(lines) != len(s['lines']):
        raise ValueError('SRI_AUTHORIZATION_LINES_MISMATCH')
    for actual, line in zip(lines, s['lines']):
        def value(path):
            nodes = actual.findall(path)
            if len(nodes) != 1 or nodes[0].text is None:
                raise ValueError('SRI_AUTHORIZATION_LINES_MISMATCH')
            return nodes[0].text.strip()
        rate = number(line['tax_rate'])
        base = cents(number(line['quantity']) * number(line['unit_price']))
        if (value('codigoPrincipal') != str(line['code'] or 'SIN-CODIGO')
                or value('descripcion') != str(line['description']).strip()
                or number(value('cantidad')) != number(line['quantity'])
                or number(value('precioUnitario')) != number(line['unit_price'])
                or number(value('descuento')) != 0
                or cents(value('precioTotalSinImpuesto')) != base
                or len(actual.findall('impuestos/impuesto')) != 1
                or value('impuestos/impuesto/codigo') != '2'
                or value('impuestos/impuesto/codigoPorcentaje') != TAX_CODES[rate]
                or number(value('impuestos/impuesto/tarifa')) != rate
                or cents(value('impuestos/impuesto/baseImponible')) != base
                or cents(value('impuestos/impuesto/valor')) != cents(base * rate / 100)):
            raise ValueError('SRI_AUTHORIZATION_LINES_MISMATCH')
    return xml.encode('utf-8')


class OpenApiSriClient:
    def __init__(self, session=None, env=None):
        self.env = os.environ if env is None else env
        self.session = session or requests.Session()
        self.url = self.env.get('SRI_OPENAPI_URL', '').rstrip('/')
        parts = urlsplit(self.url)
        if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment:
            raise ValueError('SRI_OPENAPI_URL_REQUIRED')
        if self.env.get('SRI_OPENAPI_ENVIRONMENT') not in ENVIRONMENTS:
            raise ValueError('SRI_OPENAPI_ENVIRONMENT_REQUIRED')
        if not all(self.env.get(k) for k in ('SRI_OPENAPI_EMAIL', 'SRI_OPENAPI_PASSWORD', 'SRI_ISSUER_RUC')):
            raise ValueError('SRI_OPENAPI_CREDENTIALS_REQUIRED')
        # Explicit operator attestation, not an inference from upstream defaults.
        if self.env.get('SRI_OPENAPI_SYNC_CONFIRMED') != 'true':
            raise ValueError('SRI_OPENAPI_SYNC_REQUIRED')
        self.token = None

    def check(self, issue):
        if issue['issuer_ruc'] != self.env['SRI_ISSUER_RUC']:
            raise ValueError('SRI_CERTIFICATE_ISSUER_MISMATCH')
        if issue['environment'] != self.env['SRI_OPENAPI_ENVIRONMENT']:
            raise ValueError('SRI_OPENAPI_ENVIRONMENT_MISMATCH')
        if issue['environment'] == 'produccion' and self.env.get('SRI_PRODUCTION_ENABLED') != 'true':
            raise ValueError('SRI_PRODUCTION_NOT_ENABLED')
        return factura_payload(issue, self.env.get('SRI_OPENAPI_ACCOUNTING', ''))

    def request(self, method, path, *, payload=None, params=None, binary=False, login=False):
        headers = {'Accept': 'application/pdf' if binary else 'application/json'}
        if not login:
            if not self.token:
                auth = self.request('POST', '/auth/login', login=True, payload={
                    'email': self.env['SRI_OPENAPI_EMAIL'], 'password': self.env['SRI_OPENAPI_PASSWORD']})
                self.token = auth.get('accessToken')
                if not isinstance(self.token, str) or not self.token or '\n' in self.token or '\r' in self.token:
                    raise ValueError('SRI_OPENAPI_AUTH_FAILED')
            headers['Authorization'] = 'Bearer ' + self.token
        try:
            # Never retry or follow redirects, especially a fiscal emission POST.
            with self.session.request(method, self.url + path, json=payload, params=params,
                                      headers=headers, timeout=(5, 25), allow_redirects=False, stream=True) as response:
                if not 200 <= response.status_code < 300:
                    raise ValueError('SRI_OPENAPI_HTTP_' + str(response.status_code))
                chunks, size = [], 0
                for chunk in response.iter_content(65536):
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise ValueError('SRI_OPENAPI_RESPONSE_TOO_LARGE')
                    chunks.append(chunk)
                raw = b''.join(chunks)
        except requests.RequestException as exc:
            # Do not expose URLs, tokens, credentials or upstream response bodies.
            raise ValueError('SRI_OPENAPI_TRANSPORT_UNCERTAIN') from exc
        if binary:
            if not raw.startswith(b'%PDF-'):
                raise ValueError('SRI_INVALID_RIDE')
            return raw
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeError) as exc:
            raise ValueError('SRI_OPENAPI_INVALID_RESPONSE') from exc
        if not isinstance(data, dict):
            raise ValueError('SRI_OPENAPI_INVALID_RESPONSE')
        return data

    def preflight(self, issue):
        payload = self.check(issue)
        # Preview validates tenant access and DTO without signing or emission.
        result = self.request('POST', '/sri/preview/factura', payload=payload)
        if not isinstance(result.get('xml'), str):
            raise ValueError('SRI_OPENAPI_PREVIEW_FAILED')
        return {'ready': True, 'provider': 'openapi'}

    def submit(self, issue):
        payload = self.check(issue)
        result = self.request('POST', '/sri/emitir/factura', payload=payload)
        if result.get('estado') == 'EN_COLA':
            # This violates the synchronous deployment contract. Keep the claim.
            return {'status': 'processing', 'provider_status': 'EN_COLA', 'review_required': True}
        key = validate_key(result.get('claveAcceso'), issue)
        status = 'rejected' if result.get('estado') in REJECTED else 'processing'
        return {'status': status, 'access_key': key, 'numeric_code': key[39:47],
                'provider_status': str(result.get('estado', 'DESCONOCIDO'))[:40]}

    def lookup(self, issue):
        found = []
        for page in range(1, 11):
            response = self.request('GET', '/sri/comprobantes', params={
                'rucEmisor': issue['issuer_ruc'], 'tipoComprobante': '01',
                'establecimiento': issue['establishment'], 'puntoEmision': issue['emission_point'],
                'fechaDesde': issue['snapshot']['issue_date'], 'fechaHasta': issue['snapshot']['issue_date'],
                'page': page, 'limit': 100})
            rows = response.get('data')
            if not isinstance(rows, list):
                raise ValueError('SRI_OPENAPI_INVALID_RESPONSE')
            for row in rows:
                if (str(row.get('secuencial', '')).zfill(9) == issue['sequential']
                        and str(row.get('ambiente')) == ENVIRONMENTS[issue['environment']]):
                    if (row.get('rucEmisor') != issue['issuer_ruc']
                            or row.get('establecimiento') != issue['establishment']
                            or row.get('puntoEmision') != issue['emission_point']
                            or row.get('identificacionComprador') != issue['snapshot']['identification']
                            or cents(row.get('total', '-1')) != cents(issue['snapshot']['total'])):
                        raise ValueError('SRI_OPENAPI_SERIES_COLLISION')
                    found.append(validate_key(row.get('claveAcceso'), issue))
            pages = response.get('meta', {}).get('totalPages')
            more = response.get('hasMore')
            if (isinstance(pages, int) and page >= pages) or more is False or (pages is None and more is None and len(rows) < 100):
                break
        else:
            raise ValueError('SRI_OPENAPI_RECONCILIATION_LIMIT')
        if len(found) > 1:
            raise ValueError('SRI_OPENAPI_SERIES_COLLISION')
        return found[0] if found else None

    def refresh(self, issue):
        self.check(issue)
        key = issue.get('access_key') or self.lookup(issue)
        if not key:
            # No absence proof: the upstream process may have crashed after SOAP.
            return {'status': 'processing', 'review_required': True,
                    'provider_status': 'RECONCILIATION_REQUIRED'}
        validate_key(key, issue)
        base = {'access_key': key, 'numeric_code': key[39:47]}
        result = self.request('GET', '/sri/autorizar/' + key)
        if result.get('claveAcceso') != key:
            raise ValueError('SRI_ACCESS_KEY_MISMATCH')
        status = result.get('estado')
        if status != 'AUTORIZADO':
            return {**base, 'status': 'rejected' if status in REJECTED else 'processing',
                    'provider_status': str(status or 'DESCONOCIDO')[:40]}
        if result.get('success') is not True or result.get('numeroAutorizacion') != key:
            raise ValueError('SRI_INVALID_AUTHORIZATION')
        when = result.get('fechaAutorizacion', '')
        try:
            parsed = datetime.fromisoformat(when.replace('Z', '+00:00'))
            if not parsed.tzinfo:
                raise ValueError('Missing timezone')
        except (ValueError, TypeError, AttributeError) as exc:
            raise ValueError('SRI_INVALID_AUTHORIZATION_DATE') from exc
        xml = signed_invoice(result.get('xmlAutorizado'), issue, key)
        # RIDE uses the upstream stored document. Never archive a provisional PDF.
        stored = self.request('GET', '/sri/comprobantes/' + key)
        if stored.get('claveAcceso') != key or stored.get('estado') != 'AUTORIZADO':
            return {**base, 'status': 'processing', 'provider_status': 'AUTHORIZED_ARCHIVE_PENDING', 'review_required': True}
        pdf = self.request('GET', '/sri/comprobantes/' + key + '/ride', binary=True)
        wrapper = ET.Element('autorizacion')
        for tag, value in [('estado', 'AUTORIZADO'), ('numeroAutorizacion', key),
                           ('fechaAutorizacion', when), ('ambiente', 'PRUEBAS' if issue['environment'] == 'pruebas' else 'PRODUCCION'),
                           ('comprobante', xml.decode('utf-8'))]:
            ET.SubElement(wrapper, tag).text = value
        authorized = ET.tostring(wrapper, encoding='utf-8', xml_declaration=True)
        if len(authorized) > MAX_BYTES:
            raise ValueError('SRI_OPENAPI_RESPONSE_TOO_LARGE')
        encode = lambda value: base64.b64encode(value).decode('ascii')
        return {**base, 'status': 'authorized', 'authorization': key, 'authorized_at': when,
                'signed_xml': encode(xml), 'authorized_xml': encode(authorized), 'ride_pdf': encode(pdf),
                'provider_status': 'AUTORIZADO'}
