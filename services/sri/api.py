"""Private signer/transport service for the Coco Supabase Edge Function.

Run behind HTTPS; the PKCS#12 and password are environment-only and never
returned to the browser or saved in the database.
"""
import base64
import asyncio
import hashlib
import hmac
import json
import os
import smtplib
from email.message import EmailMessage
from fastapi import FastAPI, HTTPException, Request
from .openapi import OpenApiSriClient
from .reconcile import lifespan, configuration as reconcile_configuration
from .engine import access_key, document_xml, sign_xml, send_sri, authorize_sri, ride_pdf

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)


def validate(issue):
    if issue['issuer_ruc'] != os.environ['SRI_ISSUER_RUC']:
        raise ValueError('SRI_CERTIFICATE_ISSUER_MISMATCH')
    if issue['environment'] not in ('pruebas', 'produccion'):
        raise ValueError('SRI_ENVIRONMENT_INVALID')
    if issue['environment'] == 'produccion' and os.getenv('SRI_PRODUCTION_ENABLED') != 'true':
        raise ValueError('SRI_PRODUCTION_NOT_ENABLED')


def notify(issue, xml, pdf):
    email = issue['snapshot'].get('customer_email')
    if not email:
        raise ValueError('SRI_CUSTOMER_EMAIL_MISSING')
    msg = EmailMessage()
    msg['Subject'] = 'Comprobante electronico ' + issue['establishment'] + '-' + issue['emission_point'] + '-' + issue['sequential']
    msg['From'] = os.environ['SRI_SMTP_FROM']
    msg['To'] = email
    msg.set_content('Adjuntamos el comprobante electronico autorizado por el SRI y su RIDE.')
    msg.add_attachment(xml, maintype='application', subtype='xml', filename=access_key(issue) + '.xml')
    msg.add_attachment(pdf, maintype='application', subtype='pdf', filename=access_key(issue) + '.pdf')
    with smtplib.SMTP_SSL(os.environ['SRI_SMTP_HOST'], int(os.getenv('SRI_SMTP_PORT', '465')), timeout=20) as smtp:
        smtp.login(os.environ['SRI_SMTP_USER'], os.environ['SRI_SMTP_PASSWORD'])
        smtp.send_message(msg)


@app.post('/execute')
async def execute(request: Request):
    limit = 2_000_000
    try:
        if int(request.headers.get('content-length', '0')) > limit:
            raise HTTPException(413, 'PAYLOAD_TOO_LARGE')
    except ValueError:
        raise HTTPException(400, 'INVALID_CONTENT_LENGTH')
    chunks = []
    size = 0
    try:
        async with asyncio.timeout(15):
            async for chunk in request.stream():
                size += len(chunk)
                if size > limit:
                    raise HTTPException(413, 'PAYLOAD_TOO_LARGE')
                chunks.append(chunk)
    except TimeoutError:
        raise HTTPException(408, 'PAYLOAD_TIMEOUT')
    body = b''.join(chunks)
    expected = hmac.new(os.environ['SRI_WORKER_SECRET'].encode(), body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(request.headers.get('x-sri-signature', ''), expected):
        raise HTTPException(401, 'UNAUTHORIZED')
    try:
        data = json.loads(body)
        action = data['action']
        if action == 'status':
            provider = os.getenv('SRI_PROVIDER', 'private_worker')
            if provider == 'openapi':
                OpenApiSriClient()  # Validate configuration; not a certification claim.
                ready = os.getenv('SRI_OPENAPI_ACCOUNTING') in ('SI', 'NO')
            else:
                ready = provider == 'private_worker' and bool(os.getenv('SRI_P12_BASE64') and os.getenv('SRI_P12_PASSWORD'))
            documents = ['01', '03', '04', '06', '07'] if provider == 'private_worker' else ['01', '04', '06', '07']
            if os.getenv('SRI_P12_BASE64') and os.getenv('SRI_P12_PASSWORD') and '03' not in documents:
                documents.append('03')
            return {'configured': ready, 'provider': provider, 'document_types': documents,
                    'reconciliation_enabled': reconcile_configuration() is not None,
                    'environment': os.getenv('SRI_OPENAPI_ENVIRONMENT') if provider == 'openapi' else None}
        if action in ('received_inspect', 'verify_received', 'verify_received_batch'):
            from .received import inspect_authorized, verify, verify_batch
            raw=base64.b64decode(data['xml_base64'], validate=True)
            if action == 'received_inspect':
                return inspect_authorized(raw,os.environ['SRI_ISSUER_RUC'])
            invoices=data['invoices'] if action=='verify_received_batch' else [data['invoice']]
            if not isinstance(invoices,list) or not 1 <= len(invoices) <= 50 or any(not isinstance(i,dict) for i in invoices):
                raise ValueError('SRI_RECEIVED_FIELDS_INVALID')
            if any(i['issuer_ruc'] != os.environ['SRI_ISSUER_RUC'] for i in invoices):
                raise ValueError('SRI_CERTIFICATE_ISSUER_MISMATCH')
            return verify_batch(raw,invoices) if action=='verify_received_batch' else verify(raw,invoices[0])
        issue = data['issue']
        validate(issue)
        if action in ('openapi_preflight', 'openapi_submit', 'openapi_refresh'):
            # Historical Open API documents remain readable after a default-provider switch.
            if action != 'openapi_refresh' and os.getenv('SRI_PROVIDER') != 'openapi':
                raise ValueError('SRI_PROVIDER_MISMATCH')
            client = OpenApiSriClient()
            return getattr(client, action.removeprefix('openapi_'))(issue)
        if action == 'sign':
            xml, key = document_xml(issue)
            if issue.get('access_key') and issue['access_key'] != key:
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            p12 = base64.b64decode(os.environ['SRI_P12_BASE64'], validate=True)
            signed = sign_xml(xml, p12, os.environ['SRI_P12_PASSWORD'])
            return {'access_key': key, 'signed_xml': base64.b64encode(signed).decode()}
        if action == 'receive':
            if issue['access_key'] != access_key(issue):
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            return send_sri(base64.b64decode(data['signed_xml'], validate=True), issue['access_key'], issue['environment'])
        if action == 'authorize':
            if issue['access_key'] != access_key(issue):
                raise ValueError('SRI_ACCESS_KEY_MISMATCH')
            response = authorize_sri(issue['access_key'], issue['environment'])
            if response['status'] == 'authorized':
                from .openapi import signed_invoice
                signed_invoice(response['authorized_xml'], issue, issue['access_key'])
                issue['authorization'] = response['authorization']
                response['ride_pdf'] = base64.b64encode(ride_pdf(issue)).decode()
                response['authorized_xml'] = base64.b64encode(response['authorized_xml'].encode()).decode()
            return response
        if action == 'notify':
            if issue['status'] != 'authorized' or issue['authorization'] != issue['access_key']:
                raise ValueError('SRI_NOT_AUTHORIZED')
            notify(issue, base64.b64decode(data['authorized_xml'], validate=True),
                   base64.b64decode(data['ride_pdf'], validate=True))
            return {'delivered': True}
        raise ValueError('UNKNOWN_ACTION')
    except (ValueError, KeyError) as exc:
        # Only controlled codes cross the private gateway boundary.
        code = str(exc)
        if not code.startswith(('SRI_', 'INVALID_', 'UNKNOWN_')) or len(code) > 100:
            code = 'SRI_WORKER_VALIDATION_FAILED'
        raise HTTPException(422, code) from exc
