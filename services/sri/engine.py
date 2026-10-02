"""SRI invoice adapter. The caller owns persistence and retries; secrets stay server-side.

Based on the SRI offline technical sheet v2.34. The third-party Odoo module
informed the workflow, but no Odoo code is copied or loaded here.
"""
import base64
from collections import defaultdict
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from io import BytesIO
from xml.etree import ElementTree as ET

TAX_CODES = {Decimal('0'): '0', Decimal('5'): '5', Decimal('12'): '2', Decimal('13'): '10', Decimal('14'): '3', Decimal('15'): '4'}


def cents(value):
    return Decimal(str(value)).quantize(Decimal('.01'), rounding=ROUND_HALF_UP)


def access_key(issue):
    day = date.fromisoformat(issue['snapshot']['issue_date']).strftime('%d%m%Y')
    body = ''.join((day, '01', issue['issuer_ruc'],
                    '1' if issue['environment'] == 'pruebas' else '2',
                    issue['establishment'], issue['emission_point'], issue['sequential'],
                    issue['numeric_code'], '1'))
    if len(body) != 48 or not body.isascii() or not body.isdigit():
        raise ValueError('INVALID_ACCESS_KEY_COMPONENTS')
    total = sum(int(ch) * (i % 6 + 2) for i, ch in enumerate(reversed(body)))
    digit = 11 - total % 11
    return body + str(0 if digit == 11 else 1 if digit == 10 else digit)


def element(parent, tag, value):
    ET.SubElement(parent, tag).text = str(value)


def invoice_xml(issue):
    """Only plain domestic invoices with 0/5/12/13/14/15 percent VAT.

    Other regimes (ICE, RIMPE, withholding, export, etc.) require separate
    mappings and are rejected before anything is submitted to the SRI.
    """
    snapshot = issue['snapshot']
    lines = snapshot['lines']
    if not lines:
        raise ValueError('SRI_LINES_MISSING')
    key = access_key(issue)
    groups = defaultdict(lambda: [Decimal('0'), Decimal('0')])
    net = tax = Decimal('0')
    for line in lines:
        rate = Decimal(str(line['tax_rate']))
        if rate not in TAX_CODES:
            raise ValueError('SRI_UNSUPPORTED_TAX_RATE')
        amount = cents(Decimal(str(line['quantity'])) * Decimal(str(line['unit_price'])))
        vat = cents(amount * rate / 100)
        groups[rate][0] += amount
        groups[rate][1] += vat
        net += amount
        tax += vat
    if (net, tax, net + tax) != (cents(snapshot['subtotal']), cents(snapshot['tax']), cents(snapshot['total'])):
        raise ValueError('SRI_TOTAL_MISMATCH')
    ident = snapshot['identification']
    if len(ident) not in (10, 13) or not ident.isdigit():
        raise ValueError('SRI_UNSUPPORTED_CUSTOMER_ID')
    root = ET.Element('factura', {'id': 'comprobante', 'version': '2.1.0'})
    info = ET.SubElement(root, 'infoTributaria')
    for tag, value in [('ambiente', '1' if issue['environment'] == 'pruebas' else '2'),
                       ('tipoEmision', '1'), ('razonSocial', snapshot['issuer']),
                       ('ruc', issue['issuer_ruc']), ('claveAcceso', key), ('codDoc', '01'),
                       ('estab', issue['establishment']), ('ptoEmi', issue['emission_point']),
                       ('secuencial', issue['sequential']), ('dirMatriz', snapshot['address'])]:
        element(info, tag, value)
    body = ET.SubElement(root, 'infoFactura')
    for tag, value in [('fechaEmision', date.fromisoformat(snapshot['issue_date']).strftime('%d/%m/%Y')),
                       ('dirEstablecimiento', snapshot['address']),
                       ('tipoIdentificacionComprador', '04' if len(ident) == 13 else '05'),
                       ('razonSocialComprador', snapshot['customer']), ('identificacionComprador', ident),
                       ('direccionComprador', snapshot['customer_address']),
                       ('totalSinImpuestos', f'{net:.2f}'), ('totalDescuento', '0.00')]:
        element(body, tag, value)
    taxes = ET.SubElement(body, 'totalConImpuestos')
    for rate, (base, value) in sorted(groups.items()):
        entry = ET.SubElement(taxes, 'totalImpuesto')
        for tag, data in [('codigo', '2'), ('codigoPorcentaje', TAX_CODES[rate]),
                          ('baseImponible', f'{base:.2f}'), ('valor', f'{value:.2f}')]:
            element(entry, tag, data)
    element(body, 'propina', '0.00')
    element(body, 'importeTotal', f'{net + tax:.2f}')
    element(body, 'moneda', 'DOLAR')
    payments = ET.SubElement(body, 'pagos')
    payment = ET.SubElement(payments, 'pago')
    if snapshot.get('payment_code') not in ('01', '16', '19', '20'):
        raise ValueError('SRI_PAYMENT_CODE_REQUIRED')
    element(payment, 'formaPago', snapshot['payment_code'])
    element(payment, 'total', f'{net + tax:.2f}')
    details = ET.SubElement(root, 'detalles')
    for line in lines:
        rate = Decimal(str(line['tax_rate']))
        amount = cents(Decimal(str(line['quantity'])) * Decimal(str(line['unit_price'])))
        detail = ET.SubElement(details, 'detalle')
        for tag, value in [('codigoPrincipal', line['code'] or 'SIN-CODIGO'),
                           ('descripcion', line['description']), ('cantidad', line['quantity']),
                           ('precioUnitario', line['unit_price']), ('descuento', '0.00'),
                           ('precioTotalSinImpuesto', f'{amount:.2f}')]:
            element(detail, tag, value)
        tax_node = ET.SubElement(ET.SubElement(detail, 'impuestos'), 'impuesto')
        for tag, value in [('codigo', '2'), ('codigoPorcentaje', TAX_CODES[rate]),
                           ('tarifa', rate), ('baseImponible', f'{amount:.2f}'),
                           ('valor', f'{cents(amount * rate / 100):.2f}')]:
            element(tax_node, tag, value)
    extra = ET.SubElement(root, 'infoAdicional')
    provider = ET.SubElement(extra, 'campoAdicional', {'nombre': 'RUC Proveedor'})
    provider.text = snapshot['provider_ruc']
    if snapshot.get('customer_email'):
        ET.SubElement(extra, 'campoAdicional', {'nombre': 'Email'}).text = snapshot['customer_email']
    return ET.tostring(root, encoding='utf-8', xml_declaration=True), key


def sign_xml(xml, p12_data, password):
    from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption
    from lxml import etree
    from signxml import methods
    from signxml.xades import XAdESSigner
    key, cert, chain = pkcs12.load_key_and_certificates(p12_data, password.encode())
    if not key or not cert or cert.not_valid_after_utc.date() < date.today():
        raise ValueError('SRI_CERTIFICATE_INVALID_OR_EXPIRED')
    private_pem = key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption())
    certificates = [c.public_bytes(Encoding.PEM) for c in [cert, *(chain or [])]]
    tree = etree.fromstring(xml, parser=etree.XMLParser(resolve_entities=False, no_network=True))
    signed = XAdESSigner(method=methods.enveloped).sign(tree, key=private_pem, cert=certificates)
    return etree.tostring(signed, encoding='utf-8', xml_declaration=True)


def send_sri(signed_xml, access, environment):
    """Consult authorization even after a transport error: a timeout can mean received."""
    from zeep import Client
    from zeep.transports import Transport
    from requests import Session
    host = 'celcer.sri.gob.ec' if environment == 'pruebas' else 'cel.sri.gob.ec'
    base = f'https://{host}/comprobantes-electronicos-ws/'
    session = Session()
    transport = Transport(session=session, timeout=12, operation_timeout=25)
    reception = Client(base + 'RecepcionComprobantesOffline?wsdl', transport=transport)
    response = reception.service.validarComprobante(signed_xml)
    status = response.estado
    if status != 'RECIBIDA':
        return {'status': 'rejected', 'receipt': str(response), 'authorization': None}
    return {'status': 'received', 'receipt': str(response), 'authorization': None}


def authorize_sri(access, environment):
    from zeep import Client
    from zeep.transports import Transport
    host = 'celcer.sri.gob.ec' if environment == 'pruebas' else 'cel.sri.gob.ec'
    transport = Transport(timeout=12, operation_timeout=25)
    response = Client(f'https://{host}/comprobantes-electronicos-ws/AutorizacionComprobantesOffline?wsdl',
                      transport=transport).service.autorizacionComprobante(access)
    records = response.autorizaciones.autorizacion if response and response.autorizaciones else []
    if not records:
        return {'status': 'processing', 'authorization': None}
    record = records[0]
    if record.estado == 'AUTORIZADO' and record.numeroAutorizacion == access:
        return {'status': 'authorized', 'authorization': str(record.numeroAutorizacion),
                'authorized_xml': str(record.comprobante), 'authorized_at': str(record.fechaAutorizacion)}
    return {'status': 'rejected' if record.estado == 'NO AUTORIZADO' else 'processing',
            'authorization': str(record.estado), 'messages': str(record.mensajes)}


def ride_pdf(issue):
    from reportlab.pdfgen import canvas
    buffer = BytesIO()
    pdf = canvas.Canvas(buffer, pagesize=(595, 842))
    snapshot = issue['snapshot']
    pdf.setFont('Helvetica-Bold', 16)
    pdf.drawString(40, 790, 'FACTURA ELECTRONICA - RIDE')
    pdf.setFont('Helvetica', 10)
    rows = [snapshot['issuer'], 'RUC: ' + issue['issuer_ruc'],
            'Direccion matriz: ' + snapshot['address'],
            'Ambiente: ' + ('PRUEBAS' if issue['environment'] == 'pruebas' else 'PRODUCCION'),
            'N°: ' + '-'.join((issue['establishment'], issue['emission_point'], issue['sequential'])),
            'Clave de acceso: ' + access_key(issue), 'Autorizacion: ' + issue['authorization'],
            'Cliente: ' + snapshot['customer'], 'Identificacion: ' + snapshot['identification'],
            'Direccion comprador: ' + snapshot['customer_address'],
            'Fecha: ' + snapshot['issue_date']]
    for index, row in enumerate(rows):
        pdf.drawString(40, 755 - index * 19, str(row)[:105])
    y = 520
    pdf.line(40, y + 16, 550, y + 16)
    for line in snapshot['lines']:
        pdf.drawString(40, y, f"{line['quantity']} x {str(line['description'])[:53]}")
        pdf.drawRightString(550, y, f"{cents(line['subtotal']):.2f}")
        y -= 18
        if y < 90:
            pdf.showPage()
            y = 780
    pdf.drawRightString(550, y - 25, 'Subtotal USD: ' + f"{cents(snapshot['subtotal']):.2f}")
    pdf.drawRightString(550, y - 43, 'IVA USD: ' + f"{cents(snapshot['tax']):.2f}")
    pdf.drawRightString(550, y - 61, 'TOTAL USD: ' + f"{cents(snapshot['total']):.2f}")
    pdf.save()
    return buffer.getvalue()
