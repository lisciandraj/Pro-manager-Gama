"""Ordinary Ecuadorian 03/04/06/07 documents from immutable ERP snapshots.

Official SRI schemas are bundled; XML schema validity is checked before signing.
Foreign purchases, dividends, reimbursements, ICE and special regimes require
their own fiscal mapping and are rejected instead of silently omitted.
"""
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from functools import lru_cache
from pathlib import Path
from xml.etree import ElementTree as ET

from .engine import TAX_CODES, access_key, cents, element

TYPES = {
    '03': ('liquidacionCompra', '1.1.0', 'LiquidacionCompra_V1.1.0.xsd', 'LIQUIDACIÓN DE COMPRA'),
    '04': ('notaCredito', '1.1.0', 'NotaCredito_V1.1.0.xsd', 'NOTA DE CRÉDITO'),
    '06': ('guiaRemision', '1.1.0', 'GuiaRemision_V1.1.0.xsd', 'GUÍA DE REMISIÓN'),
    '07': ('comprobanteRetencion', '2.0.0', 'ComprobanteRetencion_V2.0.0.xsd', 'COMPROBANTE DE RETENCIÓN'),
}


def amount(value, positive=False):
    try:
        n = Decimal(str(value))
        if not n.is_finite() or n < 0 or (positive and not n):
            raise ValueError('SRI_INVALID_AMOUNT')
        return n
    except (InvalidOperation, TypeError) as exc:
        raise ValueError('SRI_INVALID_AMOUNT') from exc


def required(value, code='SRI_INCOMPLETE_SNAPSHOT'):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(code)
    return value.strip()


def day(value):
    try:
        return date.fromisoformat(value).strftime('%d/%m/%Y')
    except (ValueError, TypeError) as exc:
        raise ValueError('SRI_INVALID_DATE') from exc


def identification(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{10}|[0-9]{13}', value):
        raise ValueError('SRI_UNSUPPORTED_CUSTOMER_ID')
    return '04' if len(value) == 13 else '05'


def source_document(snapshot):
    number = snapshot.get('support_number', '')
    if not re.fullmatch(r'[0-9]{3}-[0-9]{3}-[0-9]{9}', number):
        raise ValueError('SRI_SUPPORT_DOCUMENT_REQUIRED')
    issued = snapshot.get('support_date')
    if date.fromisoformat(issued) > date.fromisoformat(snapshot['issue_date']):
        raise ValueError('SRI_SUPPORT_DOCUMENT_DATE_INVALID')
    return number, day(issued)


def accounting(parent, s, mandatory=False):
    value = s.get('accounting_obligation')
    if mandatory or value is not None:
        if value not in ('SI', 'NO'):
            raise ValueError('SRI_ACCOUNTING_OBLIGATION_REQUIRED')
        element(parent, 'obligadoContabilidad', value)


def header(issue):
    code = issue['document_type']
    if code not in TYPES:
        raise ValueError('SRI_DOCUMENT_TYPE_UNSUPPORTED')
    s = issue['snapshot']
    if any(s.get(k) for k in ('foreign_purchase', 'reimbursements', 'ice', 'dividends', 'rimpe')):
        raise ValueError('SRI_SPECIAL_REGIME_UNSUPPORTED')
    root = ET.Element(TYPES[code][0], {'id': 'comprobante', 'version': TYPES[code][1]})
    info = ET.SubElement(root, 'infoTributaria')
    key = access_key(issue)
    for tag, value in [('ambiente', '1' if issue['environment'] == 'pruebas' else '2'),
                       ('tipoEmision', '1'), ('razonSocial', required(s.get('issuer'))),
                       ('ruc', issue['issuer_ruc']), ('claveAcceso', key), ('codDoc', code),
                       ('estab', issue['establishment']), ('ptoEmi', issue['emission_point']),
                       ('secuencial', issue['sequential']), ('dirMatriz', required(s.get('address')))]:
        element(info, tag, value)
    if s.get('withholding_agent_number'):
        element(info, 'agenteRetencion', s['withholding_agent_number'])
    return root, key


def line_totals(s):
    lines = s.get('lines')
    if not isinstance(lines, list) or not lines:
        raise ValueError('SRI_LINES_MISSING')
    groups, net, tax = {}, Decimal(0), Decimal(0)
    for line in lines:
        quantity, price, rate = amount(line['quantity'], True), amount(line['unit_price']), amount(line['tax_rate'])
        if rate not in TAX_CODES:
            raise ValueError('SRI_UNSUPPORTED_TAX_RATE')
        required(line.get('description'))
        base, vat = cents(quantity * price), cents(cents(quantity * price) * rate / 100)
        if line.get('subtotal') is not None and cents(line['subtotal']) != base:
            raise ValueError('SRI_TOTAL_MISMATCH')
        previous = groups.get(rate, (Decimal(0), Decimal(0)))
        groups[rate] = (previous[0] + base, previous[1] + vat)
        net += base
        tax += vat
    if (net, tax, net + tax) != tuple(cents(amount(s[k])) for k in ('subtotal', 'tax', 'total')):
        raise ValueError('SRI_TOTAL_MISMATCH')
    return groups, net, tax


def taxes(parent, groups):
    node = ET.SubElement(parent, 'totalConImpuestos')
    for rate, (base, vat) in sorted(groups.items()):
        tax = ET.SubElement(node, 'totalImpuesto')
        for tag, value in [('codigo', '2'), ('codigoPorcentaje', TAX_CODES[rate]),
                           ('baseImponible', f'{base:.2f}'), ('valor', f'{vat:.2f}')]:
            element(tax, tag, value)


def details(parent, s, credit=False):
    node = ET.SubElement(parent, 'detalles')
    for line in s['lines']:
        d = ET.SubElement(node, 'detalle')
        base, rate = cents(amount(line['quantity'], True) * amount(line['unit_price'])), amount(line['tax_rate'])
        for tag, value in [('codigoInterno' if credit else 'codigoPrincipal', line.get('code') or 'SIN-CODIGO'),
                           ('descripcion', line['description']), ('cantidad', amount(line['quantity'])),
                           ('precioUnitario', amount(line['unit_price'])), ('descuento', '0.00'),
                           ('precioTotalSinImpuesto', f'{base:.2f}')]:
            element(d, tag, value)
        tax = ET.SubElement(ET.SubElement(d, 'impuestos'), 'impuesto')
        for tag, value in [('codigo', '2'), ('codigoPorcentaje', TAX_CODES[rate]), ('tarifa', rate),
                           ('baseImponible', f'{base:.2f}'), ('valor', f'{cents(base * rate / 100):.2f}')]:
            element(tax, tag, value)


def payments(parent, s, total):
    if s.get('payment_code') not in ('01', '16', '19', '20'):
        raise ValueError('SRI_PAYMENT_CODE_REQUIRED')
    p = ET.SubElement(ET.SubElement(parent, 'pagos'), 'pago')
    element(p, 'formaPago', s['payment_code'])
    element(p, 'total', f'{total:.2f}')


def credit_note(root, s):
    groups, net, tax = line_totals(s)
    number, issued = source_document(s)
    body = ET.SubElement(root, 'infoNotaCredito')
    for tag, value in [('fechaEmision', day(s['issue_date'])), ('dirEstablecimiento', s['address']),
                       ('tipoIdentificacionComprador', identification(s['identification'])),
                       ('razonSocialComprador', required(s.get('customer'))), ('identificacionComprador', s['identification'])]:
        element(body, tag, value)
    accounting(body, s)
    for tag, value in [('codDocModificado', '01'), ('numDocModificado', number),
                       ('fechaEmisionDocSustento', issued), ('totalSinImpuestos', f'{net:.2f}'),
                       ('valorModificacion', f'{net + tax:.2f}'), ('moneda', 'DOLAR')]:
        element(body, tag, value)
    taxes(body, groups)
    element(body, 'motivo', required(s.get('reason'), 'SRI_CREDIT_REASON_REQUIRED'))
    details(root, s, credit=True)


def purchase_liquidation(root, s):
    groups, net, tax = line_totals(s)
    kind = identification(s['identification'])
    if kind == '04':
        raise ValueError('SRI_LIQUIDATION_REQUIRES_NO_RUC')
    body = ET.SubElement(root, 'infoLiquidacionCompra')
    element(body, 'fechaEmision', day(s['issue_date']))
    element(body, 'dirEstablecimiento', s['address'])
    accounting(body, s)
    for tag, value in [('tipoIdentificacionProveedor', kind), ('razonSocialProveedor', required(s.get('customer'))),
                       ('identificacionProveedor', s['identification']), ('direccionProveedor', required(s.get('customer_address'))),
                       ('totalSinImpuestos', f'{net:.2f}'), ('totalDescuento', '0.00')]:
        element(body, tag, value)
    taxes(body, groups)
    element(body, 'importeTotal', f'{net + tax:.2f}')
    element(body, 'moneda', 'DOLAR')
    payments(body, s, net + tax)
    details(root, s)


def remittance_guide(root, s):
    first, last = s['transport_start'], s['transport_end']
    if s['issue_date'] != first:
        raise ValueError('SRI_TRANSPORT_ISSUE_DATE_MISMATCH')
    if date.fromisoformat(last) < date.fromisoformat(first):
        raise ValueError('SRI_TRANSPORT_DATES_INVALID')
    body = ET.SubElement(root, 'infoGuiaRemision')
    for tag, value in [('dirEstablecimiento', s['address']), ('dirPartida', required(s.get('departure_address'))),
                       ('razonSocialTransportista', required(s.get('carrier_name'))),
                       ('tipoIdentificacionTransportista', identification(s.get('carrier_identification'))),
                       ('rucTransportista', s['carrier_identification'])]:
        element(body, tag, value)
    accounting(body, s)
    element(body, 'fechaIniTransporte', day(first))
    element(body, 'fechaFinTransporte', day(last))
    element(body, 'placa', required(s.get('plate'), 'SRI_VEHICLE_PLATE_REQUIRED'))
    recipients = s.get('recipients')
    if not isinstance(recipients, list) or not recipients:
        raise ValueError('SRI_RECIPIENTS_MISSING')
    dest = ET.SubElement(root, 'destinatarios')
    for stop in recipients:
        identification(stop.get('identification'))
        recipient = ET.SubElement(dest, 'destinatario')
        for tag, value in [('identificacionDestinatario', stop['identification']),
                           ('razonSocialDestinatario', required(stop.get('customer'))),
                           ('dirDestinatario', required(stop.get('address'))),
                           ('motivoTraslado', required(stop.get('reason'), 'SRI_TRANSPORT_REASON_REQUIRED'))]:
            element(recipient, tag, value)
        if stop.get('support_number'):
            number, issued = source_document({**stop, 'issue_date': s['issue_date']})
            element(recipient, 'codDocSustento', '01')
            element(recipient, 'numDocSustento', number)
            if stop.get('support_authorization'):
                element(recipient, 'numAutDocSustento', stop['support_authorization'])
            element(recipient, 'fechaEmisionDocSustento', issued)
        if not stop.get('lines'):
            raise ValueError('SRI_LINES_MISSING')
        node = ET.SubElement(recipient, 'detalles')
        for line in stop['lines']:
            detail = ET.SubElement(node, 'detalle')
            element(detail, 'codigoInterno', line.get('code') or 'SIN-CODIGO')
            element(detail, 'descripcion', required(line.get('description')))
            element(detail, 'cantidad', amount(line['quantity'], True))


def withholding(root, s):
    body = ET.SubElement(root, 'infoCompRetencion')
    element(body, 'fechaEmision', day(s['issue_date']))
    element(body, 'dirEstablecimiento', s['address'])
    accounting(body, s, mandatory=True)
    for tag, value in [('tipoIdentificacionSujetoRetenido', identification(s['identification'])),
                       ('parteRel', 'SI' if s.get('related_party') is True else 'NO'),
                       ('razonSocialSujetoRetenido', required(s.get('customer'))),
                       ('identificacionSujetoRetenido', s['identification']),
                       ('periodoFiscal', date.fromisoformat(s['issue_date']).strftime('%m/%Y'))]:
        element(body, tag, value)
    number, issued = source_document(s)
    _, net, tax = line_totals(s)
    support = ET.SubElement(ET.SubElement(root, 'docsSustento'), 'docSustento')
    if s.get('support_code') not in ('01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '15'):
        raise ValueError('SRI_TAX_SUPPORT_CODE_REQUIRED')
    for tag, value in [('codSustento', s['support_code']), ('codDocSustento', s.get('support_document_type', '01')),
                       ('numDocSustento', number.replace('-', '')), ('fechaEmisionDocSustento', issued)]:
        element(support, tag, value)
    if s.get('support_authorization'):
        element(support, 'numAutDocSustento', s['support_authorization'])
    element(support, 'pagoLocExt', '01')
    element(support, 'totalSinImpuestos', f'{net:.2f}')
    element(support, 'importeTotal', f'{net + tax:.2f}')
    taxes_node = ET.SubElement(support, 'impuestosDocSustento')
    groups, _, _ = line_totals(s)
    for rate, (base, vat) in sorted(groups.items()):
        tax_node = ET.SubElement(taxes_node, 'impuestoDocSustento')
        for tag, value in [('codImpuestoDocSustento', '2'), ('codigoPorcentaje', TAX_CODES[rate]),
                           ('baseImponible', f'{base:.2f}'), ('tarifa', rate), ('valorImpuesto', f'{vat:.2f}')]:
            element(tax_node, tag, value)
    rows = s.get('withholdings')
    if not isinstance(rows, list) or not rows:
        raise ValueError('SRI_WITHHOLDING_LINES_MISSING')
    node, withheld = ET.SubElement(support, 'retenciones'), Decimal(0)
    for line in rows:
        base, rate = amount(line['base'], True), amount(line['rate'])
        code = line.get('tax_kind')
        value = cents(base * rate / 100)
        if code not in ('IR', 'IVA') or rate > 100 or value != cents(amount(line['amount'])):
            raise ValueError('SRI_WITHHOLDING_AMOUNT_INVALID')
        if not re.fullmatch(r'[0-9]{1,5}', line.get('code', '')):
            raise ValueError('SRI_WITHHOLDING_CODE_REQUIRED')
        if base > (net if code == 'IR' else tax):
            raise ValueError('SRI_WITHHOLDING_BASE_INVALID')
        row = ET.SubElement(node, 'retencion')
        for tag, data in [('codigo', '1' if code == 'IR' else '2'), ('codigoRetencion', line['code']),
                          ('baseImponible', f'{base:.2f}'), ('porcentajeRetener', rate), ('valorRetenido', f'{value:.2f}')]:
            element(row, tag, data)
        withheld += value
    if withheld > net + tax or withheld != cents(amount(s['withheld_total'])):
        raise ValueError('SRI_WITHHOLDING_AMOUNT_INVALID')
    payments(support, s, net + tax)


@lru_cache(maxsize=4)
def schema(code):
    from lxml import etree
    # Only these bundled schema paths are parsed; user XML never loads a DTD.
    parser = etree.XMLParser(no_network=True, load_dtd=False, resolve_entities=True)
    return etree.XMLSchema(etree.parse(str(Path(__file__).parent / 'schemas' / TYPES[code][2]), parser))


def validate_xml(xml, code):
    from lxml import etree
    if len(xml) > 1048576 or re.search(br'<!\s*(DOCTYPE|ENTITY)', xml, re.I):
        raise ValueError('SRI_UNSAFE_XML')
    try:
        tree = etree.fromstring(xml, etree.XMLParser(resolve_entities=False, no_network=True))
        schema(code).assertValid(tree)
    except (etree.XMLSyntaxError, etree.DocumentInvalid) as exc:
        raise ValueError('SRI_DOCUMENT_SCHEMA_INVALID') from exc
    return xml


def fiscal_document_xml(issue):
    root, key = header(issue)
    {'03': purchase_liquidation, '04': credit_note, '06': remittance_guide, '07': withholding}[issue['document_type']](root, issue['snapshot'])
    extra = ET.SubElement(root, 'infoAdicional')
    for name, value in [('Referencia ERP', issue['snapshot'].get('source_number')),
                        ('Email', issue['snapshot'].get('customer_email'))]:
        if value:
            ET.SubElement(extra, 'campoAdicional', {'nombre': name}).text = str(value)
    if not len(extra):
        root.remove(extra)
    xml = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    return validate_xml(xml, issue['document_type']), key


def signed_document(xml, issue, key):
    """Check the signed SRI result against the reserved document and its goods.

    SRI validates the signature. This is an additional schema/snapshot binding,
    not a substitute for XAdES verification or an SRI authorization.
    """
    code = issue['document_type']
    if not isinstance(xml, str):
        raise ValueError('SRI_INVALID_AUTHORIZED_XML')
    raw = validate_xml(xml.encode('utf-8'), code)
    actual = ET.fromstring(raw)
    signatures = actual.findall('{http://www.w3.org/2000/09/xmldsig#}Signature')
    if len(signatures) != 1:
        raise ValueError('SRI_UNSIGNED_AUTHORIZATION')
    expected = ET.fromstring(fiscal_document_xml({**issue, 'numeric_code': key[39:47]})[0])
    if actual.tag != expected.tag or actual.get('version') != expected.get('version'):
        raise ValueError('SRI_AUTHORIZATION_DOCUMENT_MISMATCH')
    numeric = {'cantidad', 'precioUnitario', 'descuento', 'precioTotalSinImpuesto', 'totalSinImpuestos',
               'valorModificacion', 'importeTotal', 'baseImponible', 'tarifa', 'valor', 'valorImpuesto',
               'porcentajeRetener', 'valorRetenido', 'total'}
    def compare(want, got):
        # Additional informational fields and an optional issuer trade name do
        # not change the fiscal operation. Every snapshot field must match.
        for tag in set(child.tag for child in want):
            targets, sources = want.findall(tag), got.findall(tag)
            if tag == 'infoAdicional':
                continue
            if tag == 'numAutDocSustento' and not sources:
                continue
            if len(targets) != len(sources):
                raise ValueError('SRI_AUTHORIZATION_DOCUMENT_MISMATCH')
            for left, right in zip(targets, sources):
                if len(left):
                    compare(left, right)
                else:
                    a, b = (left.text or '').strip(), (right.text or '').strip()
                    different = amount(a) != amount(b) if tag in numeric else a != b
                    if different:
                        raise ValueError('SRI_AUTHORIZATION_DOCUMENT_MISMATCH')
    compare(expected, actual)
    return raw


@lru_cache(maxsize=1)
def ride_fonts():
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    directory = Path(__file__).parent / 'fonts'
    for name, filename in [('CocoInter', 'Inter-Regular.ttf'), ('CocoInterBold', 'Inter-Bold.ttf')]:
        pdfmetrics.registerFont(TTFont(name, str(directory / filename)))
    pdfmetrics.registerFontFamily('CocoInter', normal='CocoInter', bold='CocoInterBold')


def document_ride(issue):
    """RIDE for an authorized document; generate only after exact-key approval."""
    from html import escape
    from io import BytesIO
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_RIGHT
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether
    from reportlab.graphics.barcode import code128
    code, s = issue['document_type'], issue['snapshot']
    key = access_key(issue)
    if issue.get('authorization') != key:
        raise ValueError('SRI_NOT_AUTHORIZED')
    fiscal_document_xml(issue)
    ride_fonts()
    buffer = BytesIO()
    styles = getSampleStyleSheet()
    for style in styles.byName.values():
        style.fontName = 'CocoInterBold' if 'Heading' in style.name else 'CocoInter'
    styles.add(ParagraphStyle('CocoTitle', parent=styles['Heading1'], textColor=colors.HexColor('#153743'), fontSize=18, leading=23, spaceAfter=12))
    styles.add(ParagraphStyle('CocoSmall', parent=styles['BodyText'], fontSize=8, leading=11))
    styles.add(ParagraphStyle('CocoRight', parent=styles['BodyText'], alignment=TA_RIGHT))
    text = lambda v: Paragraph(escape(str(v)), styles['BodyText'])
    small = lambda v: Paragraph(escape(str(v)), styles['CocoSmall'])
    blocks = [Paragraph(TYPES[code][3] + (' ELECTRÓNICO' if code == '07' else ' ELECTRÓNICA'), styles['CocoTitle']), text(s['issuer']),
              text('RUC: ' + issue['issuer_ruc']), text('Direccion matriz: ' + s['address']), Spacer(1, 12)]
    reference = '-'.join((issue['establishment'], issue['emission_point'], issue['sequential']))
    metadata = [['Numero fiscal', reference], ['Referencia ERP', s.get('source_number', '')],
                ['Ambiente', 'PRUEBAS' if issue['environment'] == 'pruebas' else 'PRODUCCION'],
                ['Fecha de emision', day(s['issue_date'])], ['Autorizacion', key]]
    if issue.get('authorized_at'):
        metadata.append(['Fecha de autorizacion', str(issue['authorized_at'])])
    table = Table([[small(a), small(b)] for a, b in metadata], colWidths=[120, 395], hAlign='LEFT')
    table.setStyle(TableStyle([('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f0f5f5')),
                               ('VALIGN', (0, 0), (-1, -1), 'TOP'), ('BOTTOMPADDING', (0, 0), (-1, -1), 6)]))
    blocks += [table, Spacer(1, 12), small('Clave de acceso'), code128.Code128(key, barWidth=.65, barHeight=30), small(key), Spacer(1, 18)]
    if code == '06':
        blocks += [text('Transportista: ' + s['carrier_name'] + ' / ' + s['carrier_identification']),
                   text('Vehiculo: ' + s['plate']), text('Salida: ' + s['departure_address']),
                   text('Transporte: ' + day(s['transport_start']) + ' a ' + day(s['transport_end'])), Spacer(1, 12)]
        for stop in s['recipients']:
            blocks.append(KeepTogether([Paragraph(escape(stop['customer']), styles['Heading2']),
                          text(stop['identification'] + ' / ' + stop['address']), text('Motivo: ' + stop['reason'])]))
            if stop.get('support_number'):
                blocks.append(text('Documento de sustento: ' + stop['support_number']))
            rows = [['Codigo', 'Descripcion', 'Cantidad']] + [[l.get('code') or '', l['description'], str(l['quantity'])] for l in stop['lines']]
            widths = [75, 360, 80]
            blocks.append(_ride_table(rows, widths, small))
            blocks.append(Spacer(1, 10))
    else:
        blocks += [text('Cliente' if code == '04' else 'Proveedor / sujeto retenido'),
                   text(s['customer'] + ' / ' + s['identification']), text(s['customer_address']), Spacer(1, 12)]
        if s.get('support_number'):
            blocks.append(text('Documento de sustento: ' + s['support_number'] + ' / ' + day(s['support_date'])))
        if code == '04':
            blocks.append(text('Motivo: ' + s['reason']))
        if code == '07':
            rows = [['Impuesto', 'Codigo', 'Base USD', '%', 'Retenido USD']] + [[l['tax_kind'], l['code'], f"{cents(l['base']):.2f}", str(l['rate']), f"{cents(l['amount']):.2f}"] for l in s['withholdings']]
            blocks.append(_ride_table(rows, [100, 80, 110, 80, 145], small))
            blocks.append(Paragraph('TOTAL RETENIDO USD: ' + f"{cents(s['withheld_total']):.2f}", styles['CocoRight']))
        else:
            rows = [['Codigo', 'Descripcion', 'Cantidad', 'Precio USD', 'Base USD']] + [[l.get('code') or '', l['description'], str(l['quantity']), f"{amount(l['unit_price']):.4f}", f"{cents(amount(l['quantity']) * amount(l['unit_price'])):.2f}"] for l in s['lines']]
            blocks.append(_ride_table(rows, [60, 235, 65, 80, 75], small))
            blocks += [Spacer(1, 12)] + [Paragraph(label + f"{cents(s[k]):.2f}", styles['CocoRight']) for label, k in [('Subtotal USD: ', 'subtotal'), ('IVA USD: ', 'tax'), ('TOTAL USD: ', 'total')]]
    def footer(canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor('#e98143'))
        canvas.line(40, 39, 555, 39)
        canvas.setFont('CocoInter', 8)
        canvas.drawString(40, 26, 'Representacion del comprobante electronico autorizado por el SRI')
        canvas.drawRightString(555, 26, str(doc.page))
        canvas.restoreState()
    SimpleDocTemplate(buffer, pagesize=(595, 842), leftMargin=40, rightMargin=40, topMargin=40, bottomMargin=55).build(blocks, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()


def _ride_table(rows, widths, render):
    from reportlab.lib import colors
    from reportlab.platypus import Table, TableStyle
    table = Table([[render(v) for v in row] for row in rows], colWidths=widths, repeatRows=1, hAlign='LEFT')
    table.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#edf4f5')),
                               ('VALIGN', (0, 0), (-1, -1), 'TOP'), ('LINEBELOW', (0, 0), (-1, 0), .6, colors.HexColor('#1c7383')),
                               ('BOTTOMPADDING', (0, 0), (-1, -1), 8), ('TOPPADDING', (0, 0), (-1, -1), 8)]))
    return table
