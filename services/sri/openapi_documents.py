"""DTOs for the pinned upstream's existing NC/RET/GR HTTP routes.

The upstream does not implement liquidation (03); it stays on the private
signer. No invented preview/emit endpoint or automatic emission retry.
"""
from datetime import date
from .documents import amount, day, identification, fiscal_document_xml, line_totals
from .engine import TAX_CODES, cents

ROUTES = {'01': 'factura', '04': 'nota-credito', '06': 'guia-remision', '07': 'retencion'}


def payload(issue, accounting):
    code, s = issue['document_type'], issue['snapshot']
    if code not in ('04', '06', '07'):
        raise ValueError('SRI_OPENAPI_DOCUMENT_UNSUPPORTED')
    if s.get('related_party') is True:
        # The pinned RET DTO has no related-party field.
        raise ValueError('SRI_OPENAPI_SPECIAL_REGIME_UNSUPPORTED')
    accounting = s.get('accounting_obligation') or accounting
    if accounting not in ('SI', 'NO'):
        raise ValueError('SRI_ACCOUNTING_OBLIGATION_REQUIRED')
    fiscal_document_xml(issue)
    emisor = {'ruc': issue['issuer_ruc'], 'razonSocial': s['issuer'], 'dirMatriz': s['address'],
              'dirEstablecimiento': s['address'], 'establecimiento': issue['establishment'],
              'puntoEmision': issue['emission_point'], 'obligadoContabilidad': accounting}
    if s.get('withholding_agent_number'):
        emisor['agenteRetencion'] = s['withholding_agent_number']
    data = {'ambiente': '1' if issue['environment'] == 'pruebas' else '2', 'tipoEmision': '1',
            'secuencial': issue['sequential'], 'emisor': emisor,
            'infoAdicional': [{'nombre': 'COCO_ID', 'valor': issue['id']},
                              {'nombre': 'Referencia ERP', 'valor': s['source_number']}]}
    if code == '06':
        if len(s['carrier_identification']) != 13:
            raise ValueError('SRI_OPENAPI_CARRIER_RUC_REQUIRED')
        data.update(fechaIniTransporte=day(s['transport_start']), fechaFinTransporte=day(s['transport_end']),
                    dirPartida=s['departure_address'], rucTransportista=s['carrier_identification'],
                    tipoIdentificacionTransportista=identification(s['carrier_identification']),
                    razonSocialTransportista=s['carrier_name'], placa=s['plate'], destinatarios=[])
        for stop in s['recipients']:
            row = {'tipoIdentificacionDestinatario': identification(stop['identification']),
                   'razonSocialDestinatario': stop['customer'], 'identificacionDestinatario': stop['identification'],
                   'dirDestinatario': stop['address'], 'motivoTraslado': stop['reason'],
                   'detalles': [{'codigoInterno': l.get('code') or 'SIN-CODIGO', 'descripcion': l['description'],
                                 'cantidad': float(amount(l['quantity'], True))} for l in stop['lines']]}
            if stop.get('support_number'):
                row.update(codDocSustento='01', numDocSustento=stop['support_number'], fechaEmisionDocSustento=day(stop['support_date']))
                if stop.get('support_authorization'):
                    row['numAutDocSustento'] = stop['support_authorization']
            data['destinatarios'].append(row)
        return data
    data['fechaEmision'] = day(s['issue_date'])
    buyer = {'tipoIdentificacion': identification(s['identification']), 'identificacion': s['identification'],
             'razonSocial': s['customer'], 'direccion': s['customer_address']}
    if s.get('customer_email'):
        buyer['email'] = s['customer_email']
    if code == '04':
        data.update(comprador=buyer, codDocModificado='01', numDocModificado=s['support_number'],
                    fechaEmisionDocSustento=day(s['support_date']), motivo=s['reason'], detalles=[])
        for l in s['lines']:
            rate, base = amount(l['tax_rate']), cents(amount(l['quantity']) * amount(l['unit_price']))
            data['detalles'].append({'codigoPrincipal': l.get('code') or 'SIN-CODIGO', 'descripcion': l['description'],
                'cantidad': float(amount(l['quantity'])), 'precioUnitario': float(amount(l['unit_price'])), 'descuento': 0,
                'impuestos': [{'codigo': '2', 'codigoPorcentaje': TAX_CODES[rate], 'tarifa': float(rate),
                              'baseImponible': float(base), 'valor': float(cents(base * rate / 100))}]})
        return data
    data.update(sujetoRetenido=buyer, periodoFiscal=date.fromisoformat(s['issue_date']).strftime('%m/%Y'), impuestos=[])
    groups, net, tax = line_totals(s)
    taxes = [{'codImpuestoDocSustento': '2', 'codigoPorcentaje': TAX_CODES[rate], 'baseImponible': float(base),
              'tarifa': float(rate), 'valorImpuesto': float(vat)} for rate, (base, vat) in sorted(groups.items())]
    for l in s['withholdings']:
        data['impuestos'].append({'codigo': '1' if l['tax_kind'] == 'IR' else '2', 'codigoRetencion': l['code'],
            'baseImponible': float(amount(l['base'])), 'porcentajeRetener': float(amount(l['rate'])),
            'valorRetenido': float(cents(l['amount'])), 'codDocSustento': s.get('support_document_type', '01'),
            'numDocSustento': s['support_number'], 'fechaEmisionDocSustento': day(s['support_date']),
            'totalSinImpuestos': float(net), 'importeTotal': float(net + tax), 'pagoLocExt': '01',
            'codSustento': s['support_code'], 'formaPago': s['payment_code'], 'impuestosDocSustento': taxes})
    return data
